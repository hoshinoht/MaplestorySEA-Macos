import Foundation

/// Step 6: copy the launcher's inner MapleStory.app wrapper to /Applications
/// so the game launches directly from the Dock/Launchpad.
@MainActor
struct InstallWrapperAppStep: InstallStep {
    let id = "wrapper-app"
    let title = "Install MapleStory.app to Applications"

    func isAlreadyDone(_ context: PipelineContext) async -> Bool {
        FileChecks.exists(GMSPaths.installedWrapperApp)
    }

    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws {
        guard FileChecks.exists(GMSPaths.innerWrapperApp) else {
            throw StepError("Wrapper app not found inside the GMS launcher bundle.")
        }
        do {
            try ProcessRunner.run("/usr/bin/ditto", [GMSPaths.innerWrapperApp.path, GMSPaths.installedWrapperApp.path])
        } catch {
            // /Applications not writable for this user → retry with admin rights.
            pipeline.log("Retrying copy with administrator privileges…")
            try ProcessRunner.runAsAdmin(
                shellCommand: "ditto \(ProcessRunner.shellQuote(GMSPaths.innerWrapperApp.path)) \(ProcessRunner.shellQuote(GMSPaths.installedWrapperApp.path))"
            )
        }
        pipeline.log("MapleStory.app installed to /Applications.")
    }
}
