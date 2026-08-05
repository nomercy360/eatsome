import SwiftUI
import UIKit

/// Tokens sampled from the approved redesign.
///
/// The direction is soft ice surfaces, white cards at 28pt, seven dots for the
/// week, and sentences instead of scores. Two ideas are load-bearing and worth
/// naming: `ice` is a *surface*, not an accent — the screen sits on it and
/// cards float above it — and `blue` is spent sparingly, on the one thing you
/// are meant to touch. A screen where three things are blue has no accent.
///
/// Dark values are derived rather than designed. The mock is light-only and
/// says so; these keep the app legible at night without pretending a dark
/// scheme has been approved.
enum WellieTheme {
    /// The screen itself. Barely blue, and never white — white is what a card
    /// is, and a white card on a white page is not a card.
    static let background = adaptive(light: hex(0xF7FCFF), dark: hex(0x0A1420))
    /// The soft surface: heroes, the Health strip, chips, quiet inputs.
    static let ice = adaptive(light: hex(0xEEF9FF), dark: hex(0x0F2740))
    /// A card that carries a list or a sentence.
    static let surface = adaptive(light: hex(0xFFFFFF), dark: hex(0x16202C))
    /// Inputs and inset wells inside a white card.
    static let well = adaptive(light: hex(0xF7FCFF), dark: hex(0x101B27))

    static let ink = adaptive(light: hex(0x051F44), dark: hex(0xE7F2FF))
    /// Running prose. Lighter than ink, darker than a label.
    static let body = adaptive(light: hex(0x59718F), dark: hex(0xA9C0D8))
    /// Labels, captions, secondary values.
    static let muted = adaptive(light: hex(0x8398B0), dark: hex(0x8CA3BC))
    /// Chevrons and disabled marks. Quieter than muted, never used for text
    /// that has to be read.
    static let faint = adaptive(light: hex(0xC7CBD1), dark: hex(0x4A5A6C))

    static let blue = adaptive(light: hex(0x3F8AF7), dark: hex(0x66A4FF))
    static let onAccent = Color.white
    static let attention = Color(uiColor: .systemOrange)
    static let attentionSurface = adaptive(light: hex(0xFFEFC2), dark: hex(0x3A2C10))
    static let danger = Color(uiColor: .systemRed)

    static let hairline = adaptive(light: UIColor(white: 0.24, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.12))
    /// The 1.5pt inset ring the mock puts on "not chosen" options, so an
    /// unselected control still has an edge without having a fill.
    static let outline = adaptive(light: UIColor(red: 0.51, green: 0.60, blue: 0.69, alpha: 0.30),
                                  dark: UIColor(white: 1, alpha: 0.18))

    static let screenInset: CGFloat = 18
    static let cardRadius: CGFloat = 28
    static let innerRadius: CGFloat = 18
    static let controlRadius: CGFloat = 20
    static let cardSpacing: CGFloat = 16

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }

    private static func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Surfaces

extension View {
    /// A card. `padding` is the mock's 22 everywhere except rows-in-a-list,
    /// which inset themselves and pass a small vertical figure instead.
    func wellieCard(color: Color = WellieTheme.surface, padding: CGFloat = 22) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
    }

    /// A list card: rows supply their own vertical padding so the separators
    /// between them run the full width of the inset.
    func wellieListCard(color: Color = WellieTheme.surface) -> some View {
        self.padding(.horizontal, 22)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
    }

    func wellieScreen() -> some View {
        fontDesign(.rounded)
            .foregroundStyle(WellieTheme.ink)
            .tint(WellieTheme.blue)
            .background(WellieTheme.background.ignoresSafeArea())
    }

    /// The scroll body every screen shares: one column of cards, 16 apart,
    /// inset 18 from the edges.
    func wellieColumn() -> some View {
        self.padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 6)
            .padding(.bottom, 28)
    }
}

// MARK: - Buttons

struct WelliePrimaryButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(17.5, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(WellieTheme.onAccent)
            .background(
                (enabled ? WellieTheme.blue : WellieTheme.faint)
                    .opacity(configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct WellieSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(16.5, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(WellieTheme.blue)
            .background(
                WellieTheme.ice.opacity(configuration.isPressed ? 0.7 : 1),
                in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
            )
    }
}

/// The line under a primary button — "Not now", "or add it by hand". A real
/// choice, deliberately drawn as one that costs nothing to take.
struct WellieQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(14.5, weight: .semibold))
            .frame(maxWidth: .infinity)
            .foregroundStyle(WellieTheme.muted.opacity(configuration.isPressed ? 0.6 : 1))
            .padding(.vertical, 6)
            .contentShape(Rectangle())
    }
}

// MARK: - Text

struct WellieSectionTitle: View {
    let text: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(WellieTheme.font(17, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            if let detail {
                Text(detail)
                    .font(WellieTheme.font(13.5, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Running prose inside a card.
struct WellieProse: View {
    let text: String
    var size: CGFloat = 14

    init(_ text: String, size: CGFloat = 14) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Text(text)
            .font(WellieTheme.font(size, weight: .medium))
            .foregroundStyle(WellieTheme.body)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A caption under a control: what it does, or why it is safe.
struct WellieCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(WellieTheme.font(12.5, weight: .medium))
            .foregroundStyle(WellieTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chips

/// The one chip in the app, in the three states the mock uses it in.
struct WellieChip: View {
    enum Style {
        /// What you ate, what a food is: ice fill, ink text.
        case soft
        /// The chosen option: blue fill, white text.
        case selected
        /// An option you have not taken, or a total that is only a hint.
        case outline
    }

    let text: String
    var style: Style = .soft
    var size: CGFloat = 13.5

    var body: some View {
        Text(text)
            .font(WellieTheme.font(size, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(background, in: Capsule())
            .overlay {
                if style == .outline {
                    Capsule().strokeBorder(WellieTheme.outline, lineWidth: 1.5)
                }
            }
    }

    private var foreground: Color {
        switch style {
        case .soft: WellieTheme.ink
        case .selected: WellieTheme.onAccent
        case .outline: WellieTheme.muted
        }
    }

    private var background: Color {
        switch style {
        case .soft: WellieTheme.ice
        case .selected: WellieTheme.blue
        case .outline: WellieTheme.background
        }
    }
}

// MARK: - Marks and meters

/// The filled check the week screen uses for a held habit, and the hollow
/// warning ring for the one item that slipped.
struct WellieMark: View {
    var isMet = true
    var size: CGFloat = 20

    var body: some View {
        Group {
            if isMet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(WellieTheme.onAccent, WellieTheme.blue)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(WellieTheme.attention)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .frame(width: size, height: size)
    }
}

/// A progress bar with no percentage on it. The number beside it is in
/// servings or days, which are things you can picture.
struct WellieMeter: View {
    let fraction: Double
    var height: CGFloat = 7
    var tint: Color = WellieTheme.blue

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(WellieTheme.blue.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * proxy.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - The seven dots

/// The rolling window, drawn as the thing it actually is.
///
/// A "7-day average" is an abstraction; seven dots are a week you can point at.
/// Fill is how much of each day was logged — not how well you ate — so the row
/// stays a record rather than a verdict. Today wears a ring so the row has a
/// present tense.
struct WellieWeekDots: View {
    struct Day: Identifiable {
        let id: Int
        let initials: String
        let fill: Double
        let isToday: Bool
    }

    let days: [Day]
    /// The colour showing through the ring gap around today, which has to be
    /// whatever this row is sitting on.
    var behind: Color = WellieTheme.ice
    var onTap: ((Int) -> Void)?
    var diameter: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 8) {
                    dot(day)
                    Text(day.initials)
                        .font(WellieTheme.font(11, weight: day.isToday ? .bold : .semibold))
                        .foregroundStyle(day.isToday ? WellieTheme.ink : WellieTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onTap?(day.id) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(label(for: day))
            }
        }
    }

    private func dot(_ day: Day) -> some View {
        Circle()
            .fill(day.fill > 0 ? WellieTheme.blue.opacity(0.25 + 0.75 * day.fill)
                               : WellieTheme.blue.opacity(0.16))
            .frame(width: diameter, height: diameter)
            .overlay {
                if day.isToday {
                    Circle()
                        .strokeBorder(behind, lineWidth: 3)
                        .padding(-3)
                        .background {
                            Circle()
                                .strokeBorder(WellieTheme.blue, lineWidth: 2)
                                .padding(-5)
                        }
                }
            }
    }

    private func label(for day: Day) -> String {
        let state = day.fill > 0 ? "logged" : "nothing logged"
        return day.isToday ? "Today, \(state)" : "\(day.initials), \(state)"
    }
}

// MARK: - Rows

/// The settings-style row: a label, an optional value, a chevron.
struct WellieChevronRow: View {
    let title: String
    var value: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(WellieTheme.font(15.5, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .font(WellieTheme.font(14.5, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WellieTheme.faint)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}

/// A hairline between rows inside a card, inset the way the mock draws it.
struct WellieRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(WellieTheme.hairline)
            .frame(height: 0.5)
    }
}
