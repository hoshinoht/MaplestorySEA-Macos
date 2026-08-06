import Foundation

/// Concurrent, resumable file downloader built on the system curl.
///
/// curl handles the hard parts natively and fast (HTTP/2, resume via `-C -`,
/// retries with backoff), and easily saturates a connection where a
/// Swift-side byte loop caps out. Progress is read by polling the growing
/// files on disk, so there's no need to intercept the byte stream at all.
actor Downloader {
    struct FileProgress: Sendable {
        var received: Int64 = 0
        var total: Int64 = 0
        var done = false
    }

    private let session: URLSession
    private var progress: [String: FileProgress] = [:]
    private var activeProcesses: [Process] = []
    private let onProgress: @Sendable (Int64, Int64) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
        self.onProgress = onProgress
    }

    /// Downloads all URLs into `directory`, at most `concurrency` at a time.
    /// Files already fully present are skipped; partial files are resumed.
    func downloadAll(urls: [URL], to directory: URL, concurrency: Int = 6) async throws {
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
        reportProgress(in: directory)

        let poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                await self?.reportProgress(in: directory)
            }
        }
        defer {
            poller.cancel()
            for process in activeProcesses where process.isRunning { process.terminate() }
            activeProcesses.removeAll()
        }

        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                var iterator = urls.makeIterator()
                var inFlight = 0
                while true {
                    while inFlight < concurrency, let url = iterator.next() {
                        if progress[url.lastPathComponent]?.done == true { continue }
                        inFlight += 1
                        group.addTask {
                            try await self.downloadOne(url: url, in: directory)
                        }
                    }
                    guard inFlight > 0 else { break }
                    try await group.next()
                    inFlight -= 1
                }
            }
        } catch {
            reportProgress(in: directory)
            throw error
        }
        reportProgress(in: directory)
    }

    // MARK: - Single file via curl

    private func downloadOne(url: URL, in directory: URL) async throws {
        let name = url.lastPathComponent
        let destination = directory.appendingPathComponent(name)
        let expected = progress[name]?.total ?? 0

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = [
            "--location", "--fail", "--silent", "--show-error",
            "--continue-at", "-",           // resume partial files
            "--retry", "5", "--retry-delay", "2",
            "--connect-timeout", "30",
            "--output", destination.path,
            url.absoluteString,
        ]
        let errPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errPipe

        activeProcesses.append(process)
        defer { activeProcesses.removeAll { $0 === process } }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { _ in cont.resume() }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                cont.resume(throwing: error)
            }
        }

        let status = process.terminationStatus
        let finalSize = localSize(destination)

        // curl --fail exits 22 on HTTP >= 400. A 416 for a file that is in
        // fact already complete is a success in disguise.
        if status != 0 {
            if status == 22, expected > 0, finalSize >= expected {
                markDone(name, finalSize: finalSize)
                return
            }
            let stderr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw StepError("Download of \(name) failed (curl exit \(status)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if expected > 0, finalSize < expected {
            throw StepError("Download of \(name) ended short (\(finalSize) of \(expected) bytes) — retry to resume.")
        }
        markDone(name, finalSize: finalSize)
    }

    // MARK: - Bookkeeping

    private func markDone(_ name: String, finalSize: Int64) {
        progress[name]?.received = finalSize
        if progress[name]?.total == 0 { progress[name]?.total = finalSize }
        progress[name]?.done = true
    }

    /// Sums real on-disk sizes for in-flight files; done files use their
    /// recorded size.
    private func reportProgress(in directory: URL) {
        var received: Int64 = 0
        var total: Int64 = 0
        for (name, file) in progress {
            total += file.total
            if file.done {
                received += file.received
            } else {
                let onDisk = localSize(directory.appendingPathComponent(name))
                received += file.total > 0 ? min(onDisk, file.total) : onDisk
            }
        }
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
