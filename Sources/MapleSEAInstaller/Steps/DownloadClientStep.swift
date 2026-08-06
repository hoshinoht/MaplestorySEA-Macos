import Foundation

/// Step 3: download setup.exe and every setup-N.bin into a versioned folder.
/// The .bin files are InstallShield data files that must sit next to setup.exe.
@MainActor
struct DownloadClientStep: InstallStep {
    let id = "download-client"
    let title = "Download MapleSEA client"

    func isAlreadyDone(_ context: PipelineContext) async -> Bool {
        // If the game is already installed in the bottle, the client files
        // are no longer needed at all.
        FileChecks.exists(GMSPaths.bottleDriveC.appendingPathComponent(context.region.exeRelativeToDriveC))
    }

    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws {
        guard let release = context.release, let clientDir = context.clientDir else {
            throw StepError("No release resolved — the version step must run first.")
        }

        let totalFiles = release.fileNames.count
        pipeline.log("Downloading \(totalFiles) files to \(clientDir.path) (resumable)…")

        let downloader = Downloader { received, total in
            Task { @MainActor in
                pipeline.downloadProgress = (received, total)
            }
        }
        try await downloader.downloadAll(urls: release.fileURLs, to: clientDir)

        let setupExe = clientDir.appendingPathComponent("setup.exe")
        guard FileChecks.isPEExecutable(setupExe) else {
            throw StepError("setup.exe is not a valid Windows executable — the download may be corrupt. Delete \(clientDir.path) and retry.")
        }
        pipeline.log("All client files downloaded and setup.exe verified.")
    }
}
