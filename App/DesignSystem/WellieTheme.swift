import SwiftUI
import UIKit

/// Visual tokens sampled from the supplied Wellie Figma exports. Keeping the
/// palette and SF Rounded typography here makes every screen speak the same
/// language without coupling layout code to one-off hex values.
enum WellieTheme {
    static let background = Color(uiColor: .systemBackground)
    static let elevated = adaptive(light: rgb(255, 255, 255), dark: rgb(31, 36, 43))
    static let separator = Color(uiColor: .separator)

    static let ink = adaptive(light: rgb(5, 31, 68), dark: rgb(231, 242, 255))
    static let blue = adaptive(light: rgb(63, 138, 247), dark: rgb(102, 164, 255))
    static let ice = adaptive(light: rgb(238, 249, 255), dark: rgb(10, 34, 53))
    static let softBlue = adaptive(light: rgb(242, 247, 254), dark: rgb(19, 39, 61))
    static let muted = adaptive(light: rgb(131, 152, 176), dark: rgb(145, 167, 190))
    static let card = adaptive(light: rgb(248, 249, 250), dark: rgb(23, 26, 31))
    static let lime = adaptive(light: rgb(196, 244, 52), dark: rgb(178, 225, 47))
    static let warning = adaptive(light: rgb(255, 239, 194), dark: rgb(58, 44, 16))
    static let warningText = Color(uiColor: .systemOrange)
    static let danger = Color(uiColor: .systemRed)
    static let onAccent = Color.white

    static let screenInset: CGFloat = 20
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 18

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
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
            .background(WellieTheme.background.ignoresSafeArea())
    }
}

struct WelliePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(WellieTheme.onAccent)
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
