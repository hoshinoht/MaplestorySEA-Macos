import SwiftUI

/// Modern MapleStory ("New Age" era) design language: deep night-navy field,
/// glassy translucent panels, aqua→violet gradient accents, the maple leaf
/// kept as a small signature rather than a costume.
enum MapleTheme {
    static let bgTop = Color(red: 0.10, green: 0.11, blue: 0.19)     // #1A1C30
    static let bgBottom = Color(red: 0.05, green: 0.05, blue: 0.10)  // #0D0E1A

    static let card = Color.white.opacity(0.055)
    static let cardBorder = Color.white.opacity(0.10)

    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.32)

    static let mapleOrange = Color(red: 1.00, green: 0.55, blue: 0.22)   // #FF8C38
    static let mapleOrangeDeep = Color(red: 0.93, green: 0.42, blue: 0.12) // #ED6B1F

    static let aqua = Color(red: 0.33, green: 0.78, blue: 0.96)      // #55C7F5
    static let violet = Color(red: 0.55, green: 0.48, blue: 1.00)    // #8B7BFF

    static let success = Color(red: 0.36, green: 0.85, blue: 0.54)   // #5BD98A
    static let fail = Color(red: 1.00, green: 0.42, blue: 0.37)      // #FF6B5E

    static let progressGradient = LinearGradient(
        colors: [aqua, violet], startPoint: .leading, endPoint: .trailing)
}

/// Primary action: vivid maple-orange pill with a soft glow. Secondary: quiet
/// glass pill.
struct MaplePillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : MapleTheme.textPrimary)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    prominent
                        ? AnyShapeStyle(LinearGradient(
                            colors: [MapleTheme.mapleOrange, MapleTheme.mapleOrangeDeep],
                            startPoint: .top, endPoint: .bottom))
                        : AnyShapeStyle(MapleTheme.card)
                )
            )
            .overlay(Capsule().strokeBorder(
                prominent ? Color.white.opacity(0.25) : MapleTheme.cardBorder, lineWidth: 1))
            .shadow(color: prominent ? MapleTheme.mapleOrange.opacity(0.35) : .clear,
                    radius: 10, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Thin modern progress bar with the aqua→violet accent gradient.
struct GradientProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(MapleTheme.progressGradient)
                    .frame(width: max(6, geo.size.width * fraction))
                    .shadow(color: MapleTheme.aqua.opacity(0.4), radius: 4)
                    .animation(.easeOut(duration: 0.35), value: fraction)
            }
        }
        .frame(height: 6)
    }
}

struct GlassCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14).fill(MapleTheme.card))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(MapleTheme.cardBorder, lineWidth: 1))
    }
}

extension View {
    func glassCard() -> some View { modifier(GlassCard()) }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func eta(_ seconds: Double) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s left" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s left" }
        return "\(s / 3600)h \((s % 3600) / 60)m left"
    }
}
