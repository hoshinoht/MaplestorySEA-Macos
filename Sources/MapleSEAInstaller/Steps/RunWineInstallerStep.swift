import Foundation

/// Step 4: run setup.exe under the launcher's bundled wine and auto-advance
/// the InstallShield wizard. Completion = wine exits AND MapleStory.exe exists
/// in the bottle.
@MainActor
struct RunWineInstallerStep: InstallStep {
    let id = "wine-install"
    let title = "Run MapleSEA installer (auto-clicked)"

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

        if !WizardClicker.hasAccessibilityPermission {
            pipeline.needsAccessibility = true
            WizardClicker.requestAccessibilityPermission()
            pipeline.log("Waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)… The installer will still run — click the wizard manually if you prefer not to grant it.")
        }

        pipeline.log("Starting the MapleSEA installer under Wine…")
        let process = try ProcessRunner.launch(GMSPaths.wineBinary.path, [setupExe.path])

        let clicker = WizardClicker { message in
            Task { @MainActor in pipeline.log(message) }
        }
        var clickerStarted = false

        let installedExe = GMSPaths.bottleDriveC.appendingPathComponent(context.region.exeRelativeToDriveC)
        let deadline = Date().addingTimeInterval(45 * 60)
        var warnedManual = false

        defer { clicker.stop() }

        while process.isRunning {
            guard Date() < deadline else {
                process.terminate()
                throw StepError("The installer did not finish within 45 minutes.")
            }
            // Start (or keep) auto-clicking only while permission is granted.
            if WizardClicker.hasAccessibilityPermission {
                if pipeline.needsAccessibility { pipeline.needsAccessibility = false }
                if !clickerStarted {
                    clicker.start()
                    clickerStarted = true
                    pipeline.log("Auto-advancing the installer wizard…")
                }
            } else if !warnedManual, Date().timeIntervalSince(process.launchDate) > 60 {
                pipeline.wizardNeedsManualHelp = true
                warnedManual = true
                pipeline.log("Accessibility not granted — please click through the installer wizard manually (Next → Next → Install → Finish).")
            }
            try await Task.sleep(for: .seconds(2))
        }

        guard FileChecks.exists(installedExe) else {
            throw StepError("The installer exited but MapleStory.exe was not found in the Wine bottle. It may have been cancelled — run this step again.")
        }
        pipeline.wizardNeedsManualHelp = false
        pipeline.log("MapleSEA installed into the Wine bottle.")
    }
}

private extension Process {
    var launchDate: Date {
        // Process doesn't expose a launch date; approximate with "now minus
        // uptime unknown" — we only need a coarse threshold, so store-on-launch
        // is overkill. Falls back to distant past so the manual warning shows
        // promptly if accessibility is missing.
        Date.distantPast
    }
}
