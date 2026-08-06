import Foundation

/// Step 4: run setup.exe under the launcher's bundled wine, silently.
///
/// The MapleSEA full client is an Inno Setup installer (its child process is
/// `is-XXXX.tmp` with an /SL5= flag), so /VERYSILENT installs with defaults
/// and no wizard at all. If a region's installer ignores the flags, the
/// wizard shows up and the user clicks through it — completion is detected
/// the same way either way: wine exits AND MapleStory.exe exists.
@MainActor
struct RunWineInstallerStep: InstallStep {
    let id = "wine-install"
    let title = "Run MapleSEA installer"

    func isAlreadyDone(_ context: PipelineContext) async -> Bool {
        FileChecks.exists(GMSPaths.bottleDriveC.appendingPathComponent(context.region.exeRelativeToDriveC))
    }

    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws {
        guard let clientDir = context.clientDir else {
            throw StepError("No client directory — the download step must run first.")
        }
        let setupExe = clientDir.appendingPathComponent("setup.exe")
        guard FileChecks.exists(setupExe) else {
            throw StepError("setup.exe not found in \(clientDir.path).")
        }

        pipeline.log("Running the MapleSEA installer silently (this extracts tens of GB — expect it to take a while)…")
        pipeline.log("If a setup window appears anyway, click through it (Next → Install → Finish); the install continues either way.")
        let process = try ProcessRunner.launch(
            GMSPaths.wineBinary.path,
            [setupExe.path, "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART"]
        )

        let installedExe = GMSPaths.bottleDriveC.appendingPathComponent(context.region.exeRelativeToDriveC)
        let deadline = Date().addingTimeInterval(90 * 60)

        while process.isRunning {
            guard Date() < deadline else {
                process.terminate()
                throw StepError("The installer did not finish within 90 minutes.")
            }
            try await Task.sleep(for: .seconds(2))
        }

        guard FileChecks.exists(installedExe) else {
            throw StepError("The installer exited but MapleStory.exe was not found in the Wine bottle. It may have been cancelled — run this step again.")
        }
        pipeline.log("MapleSEA installed into the Wine bottle.")
    }
}
