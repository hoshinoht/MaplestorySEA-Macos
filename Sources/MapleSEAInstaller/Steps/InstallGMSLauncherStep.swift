import AppKit
import Foundation

/// Step 1: make sure the GMS macOS launcher (and with it the Wine bottle and
/// bundled wine binary) is installed. On a fresh Mac this downloads Nexon's
/// MapleStory.pkg and installs it, then runs the launcher once so it creates
/// the Wine bottle.
@MainActor
struct InstallGMSLauncherStep: InstallStep {
    let id = "gms-launcher"
    let title = "Install MapleStory (GMS) macOS launcher"

    func isAlreadyDone(_ context: PipelineContext) async -> Bool {
        FileChecks.exists(GMSPaths.wineBinary) && FileChecks.exists(GMSPaths.bottleDriveC)
    }

    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws {
        if !FileChecks.exists(GMSPaths.launcherApp) {
            let pkg = try await obtainLauncherPkg(pipeline: pipeline)
            pipeline.log("Installing \(pkg.lastPathComponent) (admin password prompt)…")
            try ProcessRunner.runAsAdmin(shellCommand: "installer -pkg '\(pkg.path)' -target /")
        }

        guard FileChecks.exists(GMSPaths.launcherApp) else {
            throw StepError("The launcher did not appear in /Applications after installation.")
        }

        // First launch creates the Wine bottle.
        if !FileChecks.exists(GMSPaths.bottleDriveC) {
            pipeline.log("Launching the GMS launcher once to create its Wine bottle…")
            let config = NSWorkspace.OpenConfiguration()
            let app = try await NSWorkspace.shared.openApplication(at: GMSPaths.launcherApp, configuration: config)

            let deadline = Date().addingTimeInterval(5 * 60)
            while !FileChecks.exists(GMSPaths.bottleDriveC) {
                guard Date() < deadline else {
                    throw StepError("Timed out waiting for the launcher to create its Wine bottle.")
                }
                try await Task.sleep(for: .seconds(2))
            }
            // Give it a moment to finish writing, then quit it.
            try await Task.sleep(for: .seconds(5))
            app.terminate()
            pipeline.log("Wine bottle created.")
        }
    }

    /// Try to find a direct .pkg link on Nexon's launcher page; if that fails,
    /// open the page in the browser and watch ~/Downloads for the pkg.
    private func obtainLauncherPkg(pipeline: InstallPipeline) async throws -> URL {
        let downloads = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")

        // A pkg may already be sitting in Downloads from a manual attempt.
        if let existing = newestPkg(in: downloads) { return existing }

        if let direct = try? await scrapePkgURL() {
            pipeline.log("Downloading launcher pkg from \(direct.absoluteString)…")
            let (temp, _) = try await URLSession.shared.download(from: direct)
            let dest = InstallerPaths.supportDir.appendingPathComponent("MapleStory.pkg")
            try FileManager.default.createDirectory(at: InstallerPaths.supportDir, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: temp, to: dest)
            return dest
        }

        // Fallback: let the user click the download button; we watch Downloads.
        pipeline.log("Couldn't find a direct pkg link — opening Nexon's download page. Click “Download Launcher for Mac”; installation continues automatically once the pkg lands in ~/Downloads.")
        NSWorkspace.shared.open(GMSPaths.nexonLauncherPage)

        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            if let pkg = newestPkg(in: downloads), isDownloadComplete(pkg) {
                return pkg
            }
            try await Task.sleep(for: .seconds(3))
        }
        throw StepError("No MapleStory .pkg appeared in ~/Downloads. Download it from \(GMSPaths.nexonLauncherPage.absoluteString) and run this installer again.")
    }

    private func scrapePkgURL() async throws -> URL {
        var request = URLRequest(url: GMSPaths.nexonLauncherPage)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let html = String(data: data, encoding: .utf8) else { throw StepError("Unreadable page") }
        let pattern = #"https?://[^"'\s]+\.pkg"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let matchRange = Range(match.range, in: html),
              let url = URL(string: String(html[matchRange])) else {
            throw StepError("No pkg link found")
        }
        return url
    }

    private func newestPkg(in directory: URL) -> URL? {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return contents
            .filter { $0.pathExtension == "pkg" && $0.lastPathComponent.lowercased().contains("maplestory") }
            .max { a, b in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da < db
            }
    }

    /// Safari/Chrome download in progress shows up as .download/.crdownload;
    /// a bare .pkg whose size is stable for a beat is considered complete.
    private func isDownloadComplete(_ url: URL) -> Bool {
        let size1 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        Thread.sleep(forTimeInterval: 1.0)
        let size2 = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        return size1 == size2 && size2 > 0
    }
}

struct StepError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
