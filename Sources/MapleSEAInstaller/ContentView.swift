import SwiftUI

struct ContentView: View {
    @EnvironmentObject var pipeline: InstallPipeline
    @State private var showLog = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [MapleTheme.sky, MapleTheme.skyDeep],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                header
                questPanel
                if pipeline.downloadProgress.total > 0 {
                    ExpBar(fraction: downloadFraction, label: percentLabel)
                        .padding(.horizontal, 4)
                }
                if pipeline.needsAccessibility {
                    accessibilityBanner
                }
                if pipeline.wizardNeedsManualHelp {
                    manualHelpBanner
                }
                logSection
                actionRow
            }
            .padding(20)
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 2) {
            HStack(spacing: 8) {
                Text("🍁")
                    .font(.system(size: 30))
                Text("MapleSEA on Mac")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: MapleTheme.wood.opacity(0.6), radius: 0, x: 0, y: 2)
            }
            Text(pipeline.finished ? "Quest complete!" : "Quest: install MapleStorySEA")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private var questPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(pipeline.steps.enumerated()), id: \.element.id) { index, step in
                stepRow(step)
                if index < pipeline.steps.count - 1 {
                    Rectangle()
                        .fill(MapleTheme.parchmentDark)
                        .frame(height: 1)
                        .padding(.leading, 40)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(MapleTheme.parchment)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(MapleTheme.wood, lineWidth: 3)
        )
        .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
    }

    private func stepRow(_ step: StepState) -> some View {
        HStack(spacing: 12) {
            statusIcon(step.status)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(MapleTheme.textBrown)
                if case .failed(let message) = step.status {
                    Text(message)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(MapleTheme.fail)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !step.detail.isEmpty {
                    Text(step.detail)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(MapleTheme.woodLight)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusIcon(_ status: StepStatus) -> some View {
        switch status {
        case .pending:
            Circle()
                .strokeBorder(MapleTheme.woodLight, lineWidth: 2)
        case .running:
            ProgressView()
                .controlSize(.small)
                .tint(MapleTheme.orange)
        case .done, .skipped:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(status == .skipped ? MapleTheme.woodLight : MapleTheme.expGreenDeep)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(MapleTheme.fail)
        }
    }

    private var accessibilityBanner: some View {
        banner(
            icon: "hand.raised.fill",
            text: "Grant Accessibility permission so the installer wizard can be clicked for you.",
            buttonTitle: "Open Settings"
        ) {
            WizardClicker.openAccessibilitySettings()
        }
    }

    private var manualHelpBanner: some View {
        banner(
            icon: "cursorarrow.click.2",
            text: "Auto-click unavailable — click through the installer wizard (Next → Install → Finish).",
            buttonTitle: nil, action: nil
        )
    }

    private func banner(icon: String, text: String, buttonTitle: String?, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(MapleTheme.orangeDeep)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(MapleTheme.textBrown)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(MapleButtonStyle(prominent: false))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(MapleTheme.parchment))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MapleTheme.orange, lineWidth: 2))
    }

    private var logSection: some View {
        DisclosureGroup(isExpanded: $showLog) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(pipeline.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(MapleTheme.textBrown)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 8).fill(MapleTheme.parchment.opacity(0.9)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(MapleTheme.wood, lineWidth: 2))
                .onChange(of: pipeline.logLines.count) {
                    if let last = pipeline.logLines.indices.last {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        } label: {
            Text("Log")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .tint(.white)
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            if pipeline.finished {
                Button("Play MapleSEA") { pipeline.launchGame() }
                    .buttonStyle(MapleButtonStyle())
            } else {
                Button(pipeline.isRunning ? "Questing…" : hasFailure ? "Retry Quest" : "Start Quest") {
                    pipeline.start()
                }
                .buttonStyle(MapleButtonStyle())
                .disabled(pipeline.isRunning)
            }
            Spacer()
        }
    }

    // MARK: - Derived

    private var downloadFraction: Double {
        let (received, total) = pipeline.downloadProgress
        guard total > 0 else { return 0 }
        return min(1, Double(received) / Double(total))
    }

    private var percentLabel: String {
        String(format: "%.1f%%", downloadFraction * 100)
    }

    private var hasFailure: Bool {
        pipeline.steps.contains { if case .failed = $0.status { return true } else { return false } }
    }
}
