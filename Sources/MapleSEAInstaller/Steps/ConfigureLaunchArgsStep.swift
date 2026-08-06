import Foundation

/// Step 5: write .ms-launch-args into the bottle's drive_c so the Crossover
/// wrapper launches MapleSEA directly, then lock the file with the immutable
/// flag — the GMS launcher deletes it on every run otherwise.
@MainActor
struct ConfigureLaunchArgsStep: InstallStep {
    let id = "launch-args"
    let title = "Point launcher at MapleSEA"

    private func expectedContent(_ region: RegionConfig) -> String {
        """
        MS_LAUNCH_DIR="\(region.windowsInstallDir)"
        MS_LAUNCH_APP="\(region.windowsExePath)"
        MS_LAUNCH_ARGS=""

        """
    }

    func isAlreadyDone(_ context: PipelineContext) async -> Bool {
        let file = GMSPaths.launchArgsFile
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              (attrs[.immutable] as? Bool) == true,
              let content = try? String(contentsOf: file, encoding: .utf8) else {
            return false
        }
        return content == expectedContent(context.region)
    }

    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws {
        let file = GMSPaths.launchArgsFile

        // A previous run may have left an immutable copy behind.
        if FileChecks.exists(file.standardizedFileURL) {
            try? FileChecks.setImmutable(file, false)
        }
        try expectedContent(context.region).write(to: file, atomically: true, encoding: .utf8)
        try FileChecks.setImmutable(file, true)
        pipeline.log("Wrote and locked \(file.path)")
    }
}
