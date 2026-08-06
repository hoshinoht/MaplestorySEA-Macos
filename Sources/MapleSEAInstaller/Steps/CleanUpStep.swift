import Foundation

/// Step 7: delete the downloaded installer files once the game is installed.
/// The client parts are ~67 GB of dead weight after a successful install —
/// a future reinstall would fetch the then-latest version anyway.
@MainActor
struct CleanUpStep: InstallStep {
    let id = "cleanup"
    let title = "Clean up installer files"

    func isAlreadyDone(_ context: PipelineContext) async -> Bool {
        FileChecks.directorySize(InstallerPaths.supportDir) < 1_000_000
    }

    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws {
        let size = FileChecks.directorySize(InstallerPaths.supportDir)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: InstallerPaths.supportDir, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
        pipeline.setStatus(id, .running, detail: "Freed \(ByteFormat.string(size))")
        pipeline.log("Freed \(ByteFormat.string(size)) of downloaded installer files.")
    }
}
