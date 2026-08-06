import SwiftUI

/// MapleStory quest-window palette: sky blue backdrop, parchment panel,
/// wood-brown borders, signature orange, EXP-bar green.
enum MapleTheme {
    static let sky = Color(red: 0.47, green: 0.74, blue: 0.93)        // #78BDEE
    static let skyDeep = Color(red: 0.30, green: 0.56, blue: 0.82)    // #4C8FD1
    static let parchment = Color(red: 0.96, green: 0.90, blue: 0.76)  // #F5E5C2
    static let parchmentDark = Color(red: 0.91, green: 0.83, blue: 0.66) // #E8D4A8
    static let wood = Color(red: 0.42, green: 0.26, blue: 0.12)       // #6B421E
    static let woodLight = Color(red: 0.58, green: 0.38, blue: 0.19)  // #94612F
    static let orange = Color(red: 0.96, green: 0.55, blue: 0.12)     // #F58C1F
    static let orangeDeep = Color(red: 0.85, green: 0.42, blue: 0.04) // #D96B0A
    static let expGreen = Color(red: 0.66, green: 0.84, blue: 0.20)   // #A8D633
    static let expGreenDeep = Color(red: 0.45, green: 0.66, blue: 0.10) // #73A81A
    static let textBrown = Color(red: 0.29, green: 0.18, blue: 0.08)  // #4A2E14
    static let fail = Color(red: 0.82, green: 0.26, blue: 0.20)       // #D14233
}

/// Chunky rounded MapleStory button: orange face, wood border, white label.
struct MapleButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .heavy, design: .rounded))
            .foregroundStyle(prominent ? .white : MapleTheme.textBrown)
            .padding(.horizontal, 22)
            .padding(.vertical, 9)
            .background(
                Capsule().fill(
                    prominent
                        ? LinearGradient(colors: [MapleTheme.orange, MapleTheme.orangeDeep],
                                         startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [MapleTheme.parchment, MapleTheme.parchmentDark],
                                         startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(Capsule().strokeBorder(MapleTheme.wood, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
    }
}

/// The signature element: overall download progress drawn as a MapleStory
/// EXP bar — green fill with a diagonal segment sheen and "EXP" tag.
struct ExpBar: View {
    let fraction: Double
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text("EXP")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(MapleTheme.expGreenDeep))
                .overlay(Capsule().strokeBorder(MapleTheme.wood, lineWidth: 1.5))

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.35))
                    Capsule()
                        .fill(
                            LinearGradient(colors: [MapleTheme.expGreen, MapleTheme.expGreenDeep],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: max(12, geo.size.width * fraction))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                }
            }
            .frame(height: 14)
            .overlay(Capsule().strokeBorder(MapleTheme.wood, lineWidth: 2))

            Text(label)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(MapleTheme.textBrown)
                .frame(minWidth: 52, alignment: .trailing)
        }
    }
}
