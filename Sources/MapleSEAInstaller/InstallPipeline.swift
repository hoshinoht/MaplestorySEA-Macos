import Foundation
import SwiftUI

enum StepStatus: Equatable {
    case pending
    case running
    case skipped      // already done from a previous run
    case done
    case failed(String)
}

struct StepState: Identifiable {
    let id: String
    let title: String
    var status: StepStatus = .pending
    var detail: String = ""
}

/// Shared mutable context steps read from and write into as the run progresses.
final class PipelineContext {
    let region: RegionConfig
    var release: ClientRelease?
    var clientDir: URL?

    init(region: RegionConfig) {
        self.region = region
    }
}

@MainActor
protocol InstallStep {
    var id: String { get }
    var title: String { get }
    /// True if this step's outcome is already in place (idempotency / resume).
    func isAlreadyDone(_ context: PipelineContext) async -> Bool
    func run(_ context: PipelineContext, pipeline: InstallPipeline) async throws
}

@MainActor
final class InstallPipeline: ObservableObject {
    @Published var steps: [StepState] = []
    @Published var isRunning = false
    @Published var finished = false
    @Published var logLines: [String] = []
    @Published var downloadProgress: (received: Int64, total: Int64) = (0, 0)
    @Published var needsAccessibility = false
    @Published var wizardNeedsManualHelp = false

    let region: RegionConfig
    let context: PipelineContext
    private var stepImplementations: [any InstallStep] = []

    init(region: RegionConfig) {
        self.region = region
        self.context = PipelineContext(region: region)
        self.stepImplementations = [
            InstallGMSLauncherStep(),
            ResolveVersionStep(),
            DownloadClientStep(),
            RunWineInstallerStep(),
            ConfigureLaunchArgsStep(),
            InstallWrapperAppStep(),
        ]
        self.steps = stepImplementations.map { StepState(id: $0.id, title: $0.title) }
    }

    func log(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("[\(stamp)] \(message)")
    }

    func setStatus(_ id: String, _ status: StepStatus, detail: String = "") {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].status = status
        if !detail.isEmpty { steps[index].detail = detail }
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        finished = false
        Task {
            await runAll()
            isRunning = false
        }
    }

    private func runAll() async {
        for step in stepImplementations {
            // Don't re-run steps that succeeded earlier in this session.
            if let state = steps.first(where: { $0.id == step.id }),
               state.status == .done || state.status == .skipped {
                continue
            }
            if await step.isAlreadyDone(context) {
                setStatus(step.id, .skipped, detail: "Already done")
                log("\(step.title): already done, skipping")
                continue
            }
            setStatus(step.id, .running)
            log("\(step.title): starting")
            do {
                try await step.run(context, pipeline: self)
                setStatus(step.id, .done)
                log("\(step.title): done")
            } catch {
                let message = error.localizedDescription
                setStatus(step.id, .failed(message))
                log("\(step.title): FAILED — \(message)")
                return
            }
        }
        finished = true
        log("All steps complete. Launch MapleStory.app from /Applications to play!")
    }

    func launchGame() {
        NSWorkspace.shared.openApplication(
            at: GMSPaths.installedWrapperApp,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
