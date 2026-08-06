import Foundation

/// Step 2: find the latest full-client release so we never install a stale
/// version. Scrapes the official download page, falls back to CDN probing.
@MainActor
struct ResolveVersionStep: InstallStep {
    let id = "resolve-version"
    let title = "Find latest MapleSEA client version"

    func isAlreadyDone(_ context: PipelineContext) async -> Bool {
        false // always re-check; it's one HTTP request
    }

    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws {
        let resolver = VersionResolver(region: context.region)
        let release = try await resolver.resolveLatest()
        context.release = release
        context.clientDir = InstallerPaths.clientDir(version: release.version)
        pipeline.setStatus(id, .running, detail: "\(release.version), \(release.fileNames.count) files")
        pipeline.log("Latest full client: \(release.version) (\(release.fileNames.count) files at \(release.baseURL.absoluteString))")
    }
}
