import Foundation

/// The resolved latest full client: version folder plus every file to download.
struct ClientRelease: Sendable {
    let version: String          // e.g. "v252"
    let baseURL: URL             // e.g. .../full-client/v252/
    let fileNames: [String]      // setup.exe, setup-1.bin ... setup-N.bin

    var fileURLs: [URL] { fileNames.map { baseURL.appendingPathComponent($0) } }
}

enum VersionResolverError: LocalizedError {
    case pageUnparseable
    case probeFailed

    var errorDescription: String? {
        switch self {
        case .pageUnparseable:
            return "Could not find full-client links on the download page."
        case .probeFailed:
            return "Could not determine the latest client version from the CDN. Check your connection, or the CDN layout may have changed."
        }
    }
}

struct VersionResolver {
    let region: RegionConfig
    let session: URLSession

    init(region: RegionConfig, session: URLSession = .shared) {
        self.region = region
        self.session = session
    }

    /// Primary: scrape the official download page for full-client/vNNN/ links.
    /// Fallback: probe the CDN upward from the last known version.
    func resolveLatest() async throws -> ClientRelease {
        if let release = try? await resolveFromDownloadPage() {
            return release
        }
        return try await resolveByProbing()
    }

    // MARK: - Download page scraping

    func resolveFromDownloadPage() async throws -> ClientRelease {
        var request = URLRequest(url: region.downloadPageURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw VersionResolverError.pageUnparseable
        }

        // Match e.g. full-client/v252/setup.exe and full-client/v252/setup-17.bin
        let pattern = #"full-client/(v\d+(?:\.\d+)?)/setup(?:-(\d+))?\.(?:exe|bin)"#
        let regex = try NSRegularExpression(pattern: pattern)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard !matches.isEmpty else { throw VersionResolverError.pageUnparseable }

        // Group part numbers by version; pick the highest version on the page.
        var partsByVersion: [String: Set<Int>] = [:]
        var hasSetupExe: Set<String> = []
        for match in matches {
            guard let vRange = Range(match.range(at: 1), in: html) else { continue }
            let version = String(html[vRange])
            if let pRange = Range(match.range(at: 2), in: html), let part = Int(html[pRange]) {
                partsByVersion[version, default: []].insert(part)
            } else {
                hasSetupExe.insert(version)
            }
        }

        func numeric(_ v: String) -> Double { Double(v.dropFirst()) ?? 0 }
        guard let version = (Set(partsByVersion.keys).union(hasSetupExe)).max(by: { numeric($0) < numeric($1) }),
              let maxPart = partsByVersion[version]?.max(),
              hasSetupExe.contains(version) || maxPart > 0 else {
            throw VersionResolverError.pageUnparseable
        }

        let files = ["setup.exe"] + (1...maxPart).map { "setup-\($0).bin" }
        return ClientRelease(
            version: version,
            baseURL: region.fullClientBaseURL.appendingPathComponent(version),
            fileNames: files
        )
    }

    // MARK: - CDN probing fallback

    /// HEAD-probe full-client/v<N>/setup.exe upward from the last known version,
    /// then count parts by probing setup-<i>.bin until a 404.
    func resolveByProbing() async throws -> ClientRelease {
        var latest: Int? = nil
        for v in region.lastKnownVersion...(region.lastKnownVersion + 20) {
            if await urlExists(region.fullClientBaseURL.appendingPathComponent("v\(v)/setup.exe")) {
                latest = v
            } else if latest != nil {
                break // ran past the newest existing version
            }
        }
        guard let v = latest else { throw VersionResolverError.probeFailed }

        let base = region.fullClientBaseURL.appendingPathComponent("v\(v)")
        var parts = 0
        for i in 1...200 {
            if await urlExists(base.appendingPathComponent("setup-\(i).bin")) {
                parts = i
            } else {
                break
            }
        }
        guard parts > 0 else { throw VersionResolverError.probeFailed }

        let files = ["setup.exe"] + (1...parts).map { "setup-\($0).bin" }
        return ClientRelease(version: "v\(v)", baseURL: base, fileNames: files)
    }

    private func urlExists(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        guard let (_, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }
}
