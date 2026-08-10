import SwiftUI
import UIKit

/// Tokens sampled from the approved redesign — identity `9`, spec `9d`.
///
/// Rounded SF is out. The identity is Space Grotesk with IBM Plex Mono caps for
/// meta, white surfaces, hairlines instead of shadows, and photos that run to
/// the edge. Five lines hold the whole system:
///
/// - **Type.** Space Grotesk 400–700 for everything a person reads; Plex Mono,
///   uppercased, small, for meta — timestamps, counts, provenance. The split is
///   semantic rather than decorative: mono means *this is data about the thing*,
///   grotesque means *this is the thing*.
/// - **Colour.** Ink, one electric blue, olive, heart red, white.
/// - **Shape.** Radii 6–10, never a pill. Avatars are squares. Photos are
///   full-bleed with no radius, and square to 8 inside a card.
/// - **Surfaces.** White everywhere, separated by hairlines. **Ink is reserved
///   for sent text** — one dark object per exchange. That is the rule the whole
///   feed rests on: avatars, captions and photo posts stay light, so twenty
///   messages in a day read as a gallery rather than as a wall of dark blocks.
/// - **Keeps.** Olives stay the score, and every behaviour from the thread —
///   states, chips, the queue — carries over untouched.
///
/// The previous direction was soft ice surfaces and 28pt cards. `ice` survives
/// as the one tinted surface, quieter than it was: a screen of pure white with
/// no tint anywhere loses the ability to say "this block is different", and
/// hairlines alone cannot carry that on a small screen.
///
/// Dark values are derived rather than designed. The mock is light-only and
/// says so; these keep the app legible at night without pretending a dark
/// scheme has been approved.
enum WellieTheme {
    /// The screen itself. White now, not barely-blue: the gallery reading only
    /// works if the page is the same white as the cards and the hairline is
    /// what separates them.
    static let background = adaptive(light: hex(0xFFFFFF), dark: hex(0x0B0F16))
    /// The one tinted surface: heroes, the Health strip, quiet inputs.
    static let ice = adaptive(light: hex(0xF4F7FA), dark: hex(0x141A23))
    /// A card that carries a list or a sentence. White, edged by a hairline
    /// rather than lifted by a shadow.
    static let surface = adaptive(light: hex(0xFFFFFF), dark: hex(0x121820))
    /// Inputs and inset wells inside a card.
    static let well = adaptive(light: hex(0xF7F9FB), dark: hex(0x0E141C))

    /// Near-black rather than navy. It is the colour of sent text and of a
    /// title, and it is the only dark object allowed in an exchange.
    static let ink = adaptive(light: hex(0x0A0F1E), dark: hex(0xEDF2F8))
    /// Running prose. Lighter than ink, darker than a label.
    static let body = adaptive(light: hex(0x4C5F7A), dark: hex(0xA9B7C8))
    /// Labels, captions, secondary values — and every mono meta line.
    static let muted = adaptive(light: hex(0x667085), dark: hex(0x8794A5))
    /// Chevrons, disabled marks, and the rail's "now" tick — **decoration
    /// only**.
    ///
    /// Measured at 2.58:1 on white and 2.50:1 on the dark page, which is under
    /// the 3:1 floor for a non-text mark and nowhere near the 4.5:1 a label
    /// needs. It had been carrying real text — the "now" label, the staleness
    /// stamp, the "logged 19:02" note — and those moved to `muted` (4.97:1).
    /// If a thing has words in it, it does not get this colour.
    static let faint = adaptive(light: hex(0x98A2B3), dark: hex(0x4A5461))

    static let blue = adaptive(light: hex(0x2E5BFF), dark: hex(0x6E92FF))
    /// Foreground on `blue`, `danger` and `olive` — all of which stay dark
    /// enough in either scheme for white to read on them.
    static let onAccent = Color.white

    /// The one distinct object in an exchange, as a *fill*.
    ///
    /// Separate from `ink` because `ink` has two jobs that pull opposite ways.
    /// As the darkest text colour it must invert for dark mode, and it does —
    /// to near-white. As the sent-bubble and send-button fill it must stay a
    /// surface with a legible foreground, and inverting it made white text sit
    /// on a white button: the send arrow disappeared entirely, and so did every
    /// message the person had sent.
    ///
    /// So the pair is explicit and always contrasts. In dark mode the sent
    /// bubble becomes the one *light* object rather than the one dark one,
    /// which is the honest inversion of the `9d` rule: what matters is that
    /// exactly one thing per exchange is the opposite of the page.
    static let inkSurface = adaptive(light: hex(0x0A0F1E), dark: hex(0xE7EDF5))
    static let onInk = adaptive(light: hex(0xFFFFFF), dark: hex(0x0A0F1E))
    /// Olive, and it is the score's colour rather than a status colour — see
    /// `OliveMark`. Named here so nothing else reaches for it by accident.
    static let olive = adaptive(light: hex(0x7D9455), dark: hex(0x9BB374))
    /// The one warm colour, spent on a reaction and on nothing else.
    static let heart = adaptive(light: hex(0xE0525B), dark: hex(0xF4767E))
    static let attention = adaptive(light: hex(0xC7822F), dark: hex(0xE0A257))
    static let attentionSurface = adaptive(light: hex(0xFBF3E7), dark: hex(0x2E2415))
    static let danger = adaptive(light: hex(0xC24B4B), dark: hex(0xE27777))

    /// The line that does the work shadows used to. `rgba(10,15,30,.1)` from
    /// the spec, exactly.
    static let hairline = adaptive(light: UIColor(red: 10 / 255, green: 15 / 255, blue: 30 / 255, alpha: 0.10),
                                   dark: UIColor(white: 1, alpha: 0.12))
    /// A slightly stronger hairline, for a control that has an edge but no
    /// fill — what the 1.5pt inset ring used to do.
    static let outline = adaptive(light: UIColor(red: 10 / 255, green: 15 / 255, blue: 30 / 255, alpha: 0.16),
                                  dark: UIColor(white: 1, alpha: 0.20))

    static let screenInset: CGFloat = 18
    /// 6–10, never a pill. A card is 10, an inner control 8, a chip 6. The old
    /// 28 was the soft direction and reads as a different app.
    static let cardRadius: CGFloat = 10
    static let innerRadius: CGFloat = 8
    static let controlRadius: CGFloat = 8
    /// What a photo squares to *inside* a card. Full-bleed photos take none.
    static let photoRadius: CGFloat = 8
    static let chipRadius: CGFloat = 6
    static let cardSpacing: CGFloat = 14

    // MARK: - Type

    static let familyName = "SpaceGrotesk"
    /// Not a typo, and not to be "corrected".
    ///
    /// The file is `IBMPlexMono-Medium.ttf` and its PostScript name — the only
    /// name `UIFont(name:)` will answer to — is `IBMPlexMono-Medm`, abbreviated
    /// by IBM to fit an old length limit. Spelling it the obvious way returns
    /// nil, SwiftUI falls back to the system monospaced face without a word,
    /// and every meta line in the app renders in the wrong typeface while
    /// looking approximately right. Which is exactly what happened here, and
    /// what `fontsAreInstalled` now catches at launch.
    static let monoFaceName = "IBMPlexMono-Medm"

    /// Space Grotesk at a weight, scaling with the reader's text size.
    ///
    /// `Font.custom(_:size:relativeTo:)` is what makes a bundled face obey
    /// Dynamic Type: the size is the value at the Large default, and iOS scales
    /// it from the matched text style. Without the `relativeTo:` this was 209
    /// fixed point sizes and a reading-size setting that did nothing at all —
    /// which for an app used one-handed at a table excluded a lot of people for
    /// no design reason.
    ///
    /// The fallback still matters: `UIFont(name:)` returns nil if the bundled
    /// file is ever dropped from the target, and a nil font in SwiftUI is not a
    /// crash — it is a screen that silently renders in the system face while
    /// every metric here stays tuned for a different one.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard fontsAreInstalled else {
            return .system(size: size, weight: weight, design: .default)
        }
        return .custom(postScriptName(for: weight), size: size, relativeTo: textStyle(for: size))
    }

    /// Meta: a timestamp, a count, a provenance line. Uppercased by `WellieMeta`,
    /// tracked out, and small — mono at body size reads as code rather than as
    /// a caption.
    ///
    /// The floor is the platform's, not a preference. iOS puts 11 pt under
    /// everything readable, and this face was shipping at 9 – 10.5 across every
    /// timestamp and food-group line in the app. Clamping here rather than at
    /// the call sites fixes all of them at once and stops the next one being
    /// written at 9 again.
    static let metaFloor: CGFloat = 11

    static func metaFont(_ size: CGFloat = metaFloor) -> Font {
        let size = max(metaFloor, size)
        guard fontsAreInstalled else {
            return .system(size: size, weight: .medium, design: .monospaced)
        }
        return .custom(monoFaceName, size: size, relativeTo: .caption2)
    }

    /// Which system text style a size scales against.
    ///
    /// Dynamic Type does not scale every style by the same factor — the large
    /// accessibility sizes grow body text far more than a title — so matching
    /// the style to the role keeps the hierarchy intact instead of letting a
    /// caption overtake a heading at AX5.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 30...: .largeTitle
        case 24..<30: .title
        case 20..<24: .title2
        case 17..<20: .title3
        case 15..<17: .body
        case 13..<15: .subheadline
        case 11.5..<13: .footnote
        default: .caption
        }
    }

    /// Space Grotesk ships three static weights; 600 rounds to Bold rather than
    /// to Medium, because a semibold heading that renders at 500 stops being a
    /// heading.
    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .bold, .semibold, .heavy, .black: "\(familyName)-Bold"
        case .medium: "\(familyName)-Medium"
        default: "\(familyName)-Regular"
        }
    }

    /// True when the bundled faces actually registered. Read by a test, so a
    /// dropped resource fails a build rather than a design review.
    static var fontsAreInstalled: Bool {
        UIFont(name: "\(familyName)-Regular", size: 12) != nil
            && UIFont(name: "\(familyName)-Medium", size: 12) != nil
            && UIFont(name: "\(familyName)-Bold", size: 12) != nil
            && UIFont(name: monoFaceName, size: 12) != nil
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
    /// A card: white, edged by a hairline, never lifted by a shadow.
    ///
    /// The old direction floated white cards on a tinted page. This one puts
    /// white on white and lets a one-pixel line do the separating, which is
    /// what makes a screen of them read as a gallery rather than as a stack.
    func wellieCard(color: Color = WellieTheme.surface, padding: CGFloat = 18) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
    }

    /// A list card: rows supply their own vertical padding so the separators
    /// between them run the full width of the inset.
    func wellieListCard(color: Color = WellieTheme.surface) -> some View {
        self.padding(.horizontal, 18)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
    }

    func wellieScreen() -> some View {
        // No `fontDesign(.rounded)` any more: the face is set per-call by
        // `WellieTheme.font`, and a design modifier here would fight it on
        // every `Text` that forgot to ask.
        foregroundStyle(WellieTheme.ink)
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

/// Meta: mono, uppercased, tracked out, small.
///
/// The `9d` split is semantic rather than decorative. Mono caps mean *this is
/// data about the thing* — a timestamp, a count, where a figure came from — and
/// Space Grotesk means *this is the thing*. Keeping them apart is what lets a
/// card carry provenance without the provenance competing with the food.
///
/// It exists as a component rather than as a modifier because the uppercasing
/// belongs to the style: half a dozen call sites had already inlined
/// `.system(size:design:.monospaced)` plus `.textCase(.uppercase)` and were
/// drifting a point apart from each other.
struct WellieMeta: View {
    let text: String
    var size: CGFloat = 9.5
    var color: Color = WellieTheme.muted

    init(_ text: String, size: CGFloat = 9.5, color: Color = WellieTheme.muted) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(WellieTheme.metaFont(size))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A square avatar with an initial in it.
///
/// Square because `9d` says so, and the reason is the feed: a column of circles
/// reads as a contact list, where squares sit in the same grid the photos do
/// and let a post read as a gallery card. Light grayscale, never ink — the one
/// dark object in an exchange is the sent bubble, and an avatar that competes
/// with it breaks the rule that makes twenty messages readable.
struct WellieAvatar: View {
    let name: String
    var side: CGFloat = 28

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
            .fill(WellieTheme.ice)
            .frame(width: side, height: side)
            .overlay {
                Text(initial)
                    .font(WellieTheme.font(side * 0.44, weight: .bold))
                    .foregroundStyle(WellieTheme.body)
            }
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
            .accessibilityLabel(name)
    }
}

/// A photograph that runs to the edge of the screen.
///
/// `9d`: photos are full-bleed with no radius, and square to 8 only when they
/// sit inside a card. Both cases are here so no call site has to remember which
/// it is in — passing `inCard` is the decision, and the radius follows.
struct WelliePhoto: View {
    let image: UIImage
    var inCard = false
    var height: CGFloat?

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
            .clipShape(
                RoundedRectangle(
                    cornerRadius: inCard ? WellieTheme.photoRadius : 0,
                    style: .continuous
                )
            )
    }
}

extension View {
    /// Guarantee the 44 pt minimum touch target without changing what is drawn.
    ///
    /// Every icon button in this app was drawn at 32–38 pt, because that is
    /// what looks right next to 15 pt text. The HIG minimum is about the finger,
    /// not the glyph, so the frame grows and the artwork does not — and
    /// `contentShape` is what makes the grown frame actually receive the tap
    /// rather than just occupy space. The diet editor's stepper was the worst
    /// of them at 32×30, two of them adjacent.
    func wellieHitTarget(_ side: CGFloat = 44) -> some View {
        frame(minWidth: side, minHeight: side)
            .contentShape(Rectangle())
    }
}

/// Motion, or its absence.
///
/// One place to ask, so a screen cannot honour Reduce Motion in its transition
/// and ignore it in its scroll. Returns nil rather than a zero-duration
/// animation: `withAnimation(nil)` and `.animation(nil, value:)` are the
/// documented way to say "do not animate this", where a 0 s curve still
/// schedules a transaction.
enum WellieMotion {
    static func step(_ reduced: Bool) -> Animation? {
        reduced ? nil : .snappy(duration: 0.28)
    }

    static func scroll(_ reduced: Bool) -> Animation? {
        reduced ? nil : .easeOut(duration: 0.25)
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
    /// Take the whole width offered instead of hugging the text.
    ///
    /// The frame has to be inside the background, not around it: applied
    /// outside, the capsule stays the width of its label and only the invisible
    /// layout box grows, which reads as three small pills adrift in a wide row.
    var fills = false

    var body: some View {
        Text(text)
            .font(WellieTheme.font(size, weight: .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .frame(maxWidth: fills ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous))
            .overlay {
                if style == .outline {
                    RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous).strokeBorder(WellieTheme.outline, lineWidth: 1.5)
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
                RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous).fill(WellieTheme.blue.opacity(0.14))
                RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
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
    /// A full-screen list can afford 16; a sheet listing four ingredients above
    /// a Done button cannot, and the rows there are the first thing to give.
    var verticalPadding: CGFloat = 16

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
