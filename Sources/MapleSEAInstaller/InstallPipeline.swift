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
    @Published var downloadRate: Double = 0 // bytes/sec

    let region: RegionConfig
    let context: PipelineContext
    private var stepImplementations: [any InstallStep] = []
    private var progressSamples: [(Date, Int64)] = []

    /// Relative effort per step, used for one honest overall progress bar
    /// instead of six disconnected spinners.
    private let stepWeights: [String: Double] = [
        "gms-launcher": 8,
        "resolve-version": 2,
        "download-client": 62,
        "wine-install": 22,
        "launch-args": 2,
        "wrapper-app": 4,
    ]

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

    // MARK: - Derived state for the UI

    var currentStep: StepState? {
        steps.first { $0.status == .running }
    }

    var failedStep: StepState? {
        steps.first { if case .failed = $0.status { return true } else { return false } }
    }

    /// 0…1 across the whole install, weighted by step effort. The download
    /// step contributes fractionally by bytes.
    var overallProgress: Double {
        let total = stepWeights.values.reduce(0, +)
        var earned: Double = 0
        for step in steps {
            let weight = stepWeights[step.id] ?? 0
            switch step.status {
            case .done, .skipped:
                earned += weight
            case .running:
                if step.id == "download-client", downloadProgress.total > 0 {
                    earned += weight * Double(downloadProgress.received) / Double(downloadProgress.total)
                } else {
                    earned += weight * 0.35
                }
            case .pending, .failed:
                break
            }
        }
        return min(1, earned / total)
    }

    var etaSeconds: Double? {
        guard downloadRate > 1, downloadProgress.total > 0,
              currentStep?.id == "download-client" else { return nil }
        let remaining = Double(downloadProgress.total - downloadProgress.received)
        return remaining / downloadRate
    }

    // MARK: - Logging & status

    func log(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("[\(stamp)] \(message)")
    }

    func setStatus(_ id: String, _ status: StepStatus, detail: String = "") {
        guard let index = steps.firstIndex(where: { $0.id == id }) else { return }
        steps[index].status = status
        if !detail.isEmpty { steps[index].detail = detail }
    }

    func recordDownloadProgress(received: Int64, total: Int64) {
        downloadProgress = (received, total)
        let now = Date()
        progressSamples.append((now, received))
        progressSamples.removeAll { now.timeIntervalSince($0.0) > 5 }
        if let oldest = progressSamples.first, oldest.0 < now {
            let dt = now.timeIntervalSince(oldest.0)
            let bytes = Double(received - oldest.1)
            if dt > 0.5 { downloadRate = max(0, bytes / dt) }
        }
    }

    // MARK: - Run

    func start() {
        guard !isRunning else { return }
        isRunning = true
        finished = false
        // A failed step gets another chance; completed work is never redone.
        for index in steps.indices {
            if case .failed = steps[index].status {
                steps[index].status = .pending
            }
        }
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
                setStatus(step.id, .skipped, detail: "Already set up")
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
        log("Installation complete. MapleStory.app is in /Applications.")
    }

    func launchGame() {
        NSWorkspace.shared.openApplication(
            at: GMSPaths.installedWrapperApp,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
