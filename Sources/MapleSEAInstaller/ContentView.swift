import SwiftUI

struct ContentView: View {
    @EnvironmentObject var pipeline: InstallPipeline
    @State private var showLog = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [MapleTheme.bgTop, MapleTheme.bgBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header
                heroCard
                stepsCard
                logSection
                actionRow
            }
            .padding(22)
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Text("🍁")
                .font(.system(size: 26))
            VStack(alignment: .leading, spacing: 1) {
                Text("MapleSEA Installer")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(MapleTheme.textPrimary)
                Text("MapleStorySEA on Apple Silicon — no VM")
                    .font(.system(size: 11.5))
                    .foregroundStyle(MapleTheme.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Hero: one headline, one honest progress bar

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(heroTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(heroTitleColor)
                Spacer()
                if pipeline.isRunning || pipeline.finished {
                    Text(String(format: "%.0f%%", pipeline.overallProgress * 100))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(MapleTheme.textSecondary)
                }
            }

            GradientProgressBar(fraction: pipeline.finished ? 1 : pipeline.overallProgress)

            Text(heroDetail)
                .font(.system(size: 11.5))
                .foregroundStyle(MapleTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .glassCard()
    }

    private var heroTitle: String {
        if pipeline.finished { return "Ready to play" }
        if let failed = pipeline.failedStep { return "Stopped at: \(failed.title)" }
        if let current = pipeline.currentStep { return current.title }
        return "Ready to install"
    }

    private var heroTitleColor: Color {
        if pipeline.finished { return MapleTheme.success }
        if pipeline.failedStep != nil { return MapleTheme.fail }
        return MapleTheme.textPrimary
    }

    private var heroDetail: String {
        if pipeline.finished {
            return "MapleStory.app is in your Applications folder."
        }
        if let failed = pipeline.failedStep, case .failed(let message) = failed.status {
            return message
        }
        if pipeline.currentStep?.id == "download-client", pipeline.downloadProgress.total > 0 {
            var parts = [
                "\(ByteFormat.string(pipeline.downloadProgress.received)) of \(ByteFormat.string(pipeline.downloadProgress.total))"
            ]
            if pipeline.downloadRate > 1 {
                parts.append(ByteFormat.rate(pipeline.downloadRate))
            }
            if let eta = pipeline.etaSeconds {
                parts.append(ByteFormat.eta(eta))
            }
            return parts.joined(separator: " · ")
        }
        if let current = pipeline.currentStep {
            return current.detail.isEmpty ? "Working…" : current.detail
        }
        return "Downloads the official client and sets everything up. One click, no manual steps."
    }

    // MARK: - Steps

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(pipeline.steps) { step in
                stepRow(step)
            }
        }
        .padding(.vertical, 6)
        .glassCard()
    }

    private func stepRow(_ step: StepState) -> some View {
        HStack(spacing: 11) {
            statusIcon(step.status)
                .frame(width: 18, height: 18)

            Text(step.title)
                .font(.system(size: 12.5, weight: step.status == .running ? .semibold : .regular))
                .foregroundStyle(stepColor(step.status))

            Spacer()

            if step.status == .skipped {
                Text("Already set up")
                    .font(.system(size: 10.5))
                    .foregroundStyle(MapleTheme.textTertiary)
            } else if !step.detail.isEmpty, step.status == .running || step.status == .done {
                Text(step.detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(MapleTheme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6.5)
    }

    private func stepColor(_ status: StepStatus) -> Color {
        switch status {
        case .running: return MapleTheme.textPrimary
        case .done, .skipped: return MapleTheme.textSecondary
        case .failed: return MapleTheme.fail
        case .pending: return MapleTheme.textTertiary
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1.5)
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(MapleTheme.aqua)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MapleTheme.success)
        case .skipped:
            Image(systemName: "checkmark.circle")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(MapleTheme.textTertiary)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MapleTheme.fail)
        }
    }

    // MARK: - Log

    private var logSection: some View {
        DisclosureGroup(isExpanded: $showLog) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(pipeline.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(MapleTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 130)
                .glassCard()
                .onChange(of: pipeline.logLines.count) {
                    if let last = pipeline.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Details")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(MapleTheme.textSecondary)
        }
        .tint(MapleTheme.textSecondary)
    }

    // MARK: - Actions

    private var actionRow: some View {
        HStack {
            Spacer()
            if pipeline.finished {
                Button("Play MapleSEA") { pipeline.launchGame() }
                    .buttonStyle(MaplePillButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else if pipeline.isRunning {
                Button("Installing…") {}
                    .buttonStyle(MaplePillButtonStyle())
                    .disabled(true)
            } else {
                Button(pipeline.failedStep == nil ? "Install MapleSEA" : "Try Again") {
                    pipeline.start()
                }
                .buttonStyle(MaplePillButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
