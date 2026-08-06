import Foundation

/// Concurrent, resumable file downloader. Partial files are resumed with HTTP
/// Range requests, so an interrupted multi-GB client download picks up where it
/// left off instead of restarting.
actor Downloader {
    struct FileProgress: Sendable {
        var received: Int64 = 0
        var total: Int64 = 0
        var done = false
    }

    private let session: URLSession
    private var progress: [String: FileProgress] = [:]
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 24 * 60 * 60
        self.session = URLSession(configuration: config)
        self.onProgress = onProgress
    }

    /// Downloads all URLs into `directory`, at most `concurrency` at a time.
    /// Files already fully present are skipped.
    func downloadAll(urls: [URL], to directory: URL, concurrency: Int = 4) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Learn total sizes up front so overall progress is meaningful.
        for url in urls {
            let name = url.lastPathComponent
            let expected = await remoteSize(of: url)
            let existing = localSize(directory.appendingPathComponent(name))
            progress[name] = FileProgress(
                received: min(existing, expected > 0 ? expected : existing),
                total: expected,
                done: expected > 0 && existing >= expected
            )
        }
        reportProgress()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = urls.makeIterator()
            var inFlight = 0
            while true {
                while inFlight < concurrency, let url = iterator.next() {
                    if progress[url.lastPathComponent]?.done == true { continue }
                    inFlight += 1
                    group.addTask {
                        try await self.download(url: url, to: directory)
                    }
                }
                guard inFlight > 0 else { break }
                try await group.next()
                inFlight -= 1
            }
        }
    }

    private func download(url: URL, to directory: URL) async throws {
        let name = url.lastPathComponent
        let destination = directory.appendingPathComponent(name)
        let existing = localSize(destination)
        let expected = progress[name]?.total ?? 0

        var request = URLRequest(url: url)
        var resumingFrom: Int64 = 0
        if existing > 0, expected > 0, existing < expected {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
            resumingFrom = existing
        } else if existing > 0, expected > 0, existing >= expected {
            markDone(name)
            return
        }

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        // Server ignored the Range header → start over.
        if resumingFrom > 0 && http.statusCode != 206 {
            resumingFrom = 0
        }

        if resumingFrom == 0 {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        try handle.seekToEnd()
        if resumingFrom == 0 {
            try handle.truncate(atOffset: 0)
        }

        var received = resumingFrom
        var buffer = Data(capacity: 1 << 16)
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 16 {
                try handle.write(contentsOf: buffer)
                received += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                update(name, received: received)
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            received += Int64(buffer.count)
        }
        markDone(name, finalSize: received)
    }

    // MARK: - Bookkeeping

    private func update(_ name: String, received: Int64) {
        progress[name]?.received = received
        reportProgress()
    }

    private func markDone(_ name: String, finalSize: Int64? = nil) {
        if let finalSize { progress[name]?.received = finalSize }
        if let total = progress[name]?.total, total == 0, let finalSize {
            progress[name]?.total = finalSize
        }
        progress[name]?.done = true
        reportProgress()
    }

    private func reportProgress() {
        let received = progress.values.reduce(0) { $0 + $1.received }
        let total = progress.values.reduce(0) { $0 + $1.total }
        onProgress(received, total)
    }

    private func remoteSize(of url: URL) async -> Int64 {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200 else { return 0 }
        return http.expectedContentLength > 0 ? http.expectedContentLength : 0
    }

    private func localSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64).flatMap { $0 } ?? 0
    }
}
