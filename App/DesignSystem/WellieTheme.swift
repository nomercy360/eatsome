import SwiftUI

/// Visual tokens sampled from the supplied Wellie Figma exports. Keeping the
/// palette and SF Rounded typography here makes every screen speak the same
/// language without coupling layout code to one-off hex values.
enum WellieTheme {
    static let ink = Color(red: 5 / 255, green: 31 / 255, blue: 68 / 255)
    static let blue = Color(red: 63 / 255, green: 138 / 255, blue: 247 / 255)
    static let ice = Color(red: 238 / 255, green: 249 / 255, blue: 255 / 255)
    static let softBlue = Color(red: 242 / 255, green: 247 / 255, blue: 254 / 255)
    static let muted = Color(red: 131 / 255, green: 152 / 255, blue: 176 / 255)
    static let card = Color(red: 248 / 255, green: 249 / 255, blue: 250 / 255)
    static let lime = Color(red: 196 / 255, green: 244 / 255, blue: 52 / 255)
    static let warning = Color(red: 255 / 255, green: 239 / 255, blue: 194 / 255)

    static let screenInset: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 18

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

struct WellieCardModifier: ViewModifier {
    var color = WellieTheme.card
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(color, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
    }
}

extension View {
    func wellieCard(color: Color = WellieTheme.card, padding: CGFloat = 18) -> some View {
        modifier(WellieCardModifier(color: color, padding: padding))
    }

    func wellieScreen() -> some View {
        fontDesign(.rounded)
            .foregroundStyle(WellieTheme.ink)
            .tint(WellieTheme.blue)
    }
}

struct WelliePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(
                configuration.isPressed ? WellieTheme.blue.opacity(0.78) : WellieTheme.blue,
                in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct WellieSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(WellieTheme.blue)
            .background(
                configuration.isPressed ? WellieTheme.softBlue.opacity(0.7) : WellieTheme.softBlue,
                in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
            )
    }
}

struct WellieKicker: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(WellieTheme.font(12, weight: .bold))
            .tracking(1.1)
            .foregroundStyle(WellieTheme.ink)
    }
}

struct WellieChip: View {
    let text: String
    var isActive = true

    var body: some View {
        Text(text)
            .font(WellieTheme.font(12, weight: .bold))
            .foregroundStyle(isActive ? WellieTheme.ink : WellieTheme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isActive ? WellieTheme.ice : WellieTheme.card,
                in: Capsule()
            )
    }
}

struct WellieEmptyRow: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(WellieTheme.font(15, weight: .medium))
            .foregroundStyle(WellieTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wellieCard(color: WellieTheme.card)
    }
}
