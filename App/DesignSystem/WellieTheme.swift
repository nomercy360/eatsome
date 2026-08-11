import SwiftUI
import UIKit

/// Tokens sampled from the approved redesign — `App Redesign Final`, turn `4`,
/// option `4a`: *Quiet night, olive-free, days-logged stats on the main screen*.
///
/// The app is dark. Not "has a dark mode" — dark, one scheme, the way a
/// wallet or a sleep tracker is. That is a bigger change than it looks and it
/// is the reason most of this file moved:
///
/// - **Type.** Sora, 400–800, and it is the only face. The Space Grotesk /
///   IBM Plex Mono pair is gone, and with it the mono-means-metadata rule: the
///   mock says meta in Sora 600 uppercased with wide tracking, so `WellieMeta`
///   still exists and still means *this is data about the thing*, it just says
///   it with tracking instead of with a second typeface. One face is what lets
///   a 64 pt counter and an 11 pt caption on the same screen read as one object.
/// - **Colour.** A near-black page, two surfaces above it, and one periwinkle
///   accent that is spent on exactly three things: the primary button, a live
///   value, and the current selection. Olive survives as `protein` — the one
///   nutrient with a colour, because it is the one with a goal.
/// - **Shape.** Big radii, 14–26. The previous direction's 6–10-never-a-pill
///   was a light, papery system; on a dark page a hairline-edged 10 pt corner
///   reads as a table cell. These are the mock's own numbers.
/// - **Surfaces.** `surface` on `background`, separated by a 1 pt `line` — the
///   dark equivalent of the old hairline discipline, and still no shadows.
/// - **Photos.** Full-bleed and squared to `photoRadius` inside a card, exactly
///   as before. The meal detail screen runs one to the top edge under a
///   gradient, which is the one place a photo is the page rather than an object
///   on it.
///
/// Ink-is-reserved-for-sent-text is retired with the thread it governed. On a
/// dark page the scarce thing is *light*, not dark, and the rule that replaces
/// it is: one accent object per screen. `inkSurface`/`onInk` remain as the
/// light-on-dark inversion for anything that still needs to be the one bright
/// block.
enum WellieTheme {
    // MARK: - Colour
    //
    // Single values, not `adaptive` pairs. The mock is dark-only and the app
    // now says so at the root with `.preferredColorScheme(.dark)`; a light
    // half nobody designed is worse than no light half at all.

    /// The page.
    static let background = hex(0x0B0D12)
    /// A card on the page. Everything with a border is this.
    static let surface = hex(0x13161E)
    /// Inputs, wells, and anything inset *inside* a card.
    static let well = hex(0x10131A)
    /// A raised fill: an unfilled meter, a secondary control, a bar in a chart
    /// that is not being pointed at.
    static let raised = hex(0x232834)
    /// The old tinted surface. Kept as an alias so the screens that have not
    /// been redrawn yet still resolve; it is `surface` now, because a dark page
    /// only supports so many greys before they stop being distinguishable.
    static let ice = hex(0x13161E)

    /// Text.
    static let ink = hex(0xEEF1F7)
    /// Running prose — one step down from `ink`, still comfortably readable.
    static let body = hex(0xB4BDCC)
    /// Labels, captions, secondary values, every meta line.
    ///
    /// Three values lighter than the mock's `#6c7689`, which measures 4.26:1 on
    /// this page — under the 4.5:1 floor for text this size, and it carries
    /// real words on every screen here ("412 / 1,800 kcal", "Usually five to
    /// eight seconds"). `#737e92` is 4.75:1 and is not distinguishable from the
    /// mock side by side.
    static let muted = hex(0x737E92)
    /// Chevrons, empty meter segments, the dim half of a `6 / 90` — **decoration
    /// and non-text marks only**, 1.6:1 on the page. The rule the old theme
    /// wrote down survives verbatim: if a thing has words in it, it does not get
    /// this colour. The exception the mock draws and this keeps is the trailing
    /// half of a fraction, where the *figure* is the content and the denominator
    /// is scale — and it is 20 pt and adjacent to its own bright numerator.
    static let faint = hex(0x3A4152)

    /// The one accent. Periwinkle, and the mock spends it on the primary
    /// button, the current selection, and a value that is alive right now.
    static let accent = hex(0x8A97F7)
    /// Foreground on `accent` — the page colour, not white. 7.3:1.
    static let onAccent = hex(0x0B0D12)
    /// Retained name for the accent, so screens outside the five redrawn here
    /// keep resolving.
    static let blue = accent

    /// Protein, and the only nutrient with a colour of its own.
    ///
    /// It gets one because it is the only one of the five with a *goal* rather
    /// than a reference range — see `DailyTargets.protein` — so a protein bar
    /// can honestly be full or short where an energy bar can only be long or
    /// less long. The olive rating is gone; the olive is not.
    static let protein = hex(0xA3B04A)
    /// A protein bar on a day that did not reach the goal.
    static let proteinDim = hex(0x2E331F)
    /// Kept for the screens still drawing a rating.
    static let olive = protein

    /// The one bright block, for anything that has to invert against the page.
    static let inkSurface = hex(0xE7EDF5)
    static let onInk = hex(0x0B0D12)

    static let heart = hex(0xF4767E)
    static let attention = hex(0xE0A257)
    static let attentionSurface = hex(0x2A2113)
    static let danger = hex(0xE27777)

    /// The line that does the work shadows used to, and that a hairline did on
    /// white. One point, not a half: on a dark page a 0.5 pt line at 12% simply
    /// is not there.
    static let hairline = hex(0x1E2330)
    /// A slightly stronger line, for a control that has an edge and no fill.
    static let outline = hex(0x2A3040)
    /// Retained alias.
    static var line: Color { hairline }

    // MARK: - Shape

    static let screenInset: CGFloat = 20
    /// The mock's card. 22, and a 26 for the two that carry a photograph or a
    /// headline — see `heroRadius`.
    static let cardRadius: CGFloat = 22
    static let heroRadius: CGFloat = 26
    /// A control inside a card: a meter, a well, a tile.
    static let innerRadius: CGFloat = 20
    /// The primary button, which is the widest radius in the app.
    static let controlRadius: CGFloat = 24
    /// What a photo squares to inside a card.
    static let photoRadius: CGFloat = 16
    /// A chip, a tab, a small option.
    static let chipRadius: CGFloat = 16
    /// A thumbnail beside a line of text.
    static let thumbRadius: CGFloat = 14
    static let cardSpacing: CGFloat = 12

    // MARK: - Type

    static let familyName = "Sora"

    /// Sora at a weight, scaling with the reader's text size.
    ///
    /// `Font.custom(_:size:relativeTo:)` is what makes a bundled face obey
    /// Dynamic Type: the size is the value at the Large default and iOS scales
    /// it from the matched text style. The fallback matters for the same reason
    /// it always did — `UIFont(name:)` returns nil if a file is dropped from
    /// the target, and a nil font in SwiftUI is not a crash, it is a screen
    /// that renders in the system face with every metric here tuned for
    /// another one.
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard fontsAreInstalled else {
            return .system(size: size, weight: weight, design: .default)
        }
        return .custom(postScriptName(for: weight), size: size, relativeTo: textStyle(for: size))
    }

    /// Meta: a timestamp, a count, a section label, a provenance line.
    /// Uppercased and tracked out by `WellieMeta`.
    ///
    /// The floor is the platform's, not a preference — iOS puts 11 pt under
    /// everything readable. Clamping here rather than at the call sites fixes
    /// every caller at once and stops the next one being written at 9 again.
    static let metaFloor: CGFloat = 11

    static func metaFont(_ size: CGFloat = metaFloor) -> Font {
        font(max(metaFloor, size), weight: .semibold)
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

    /// Five cuts, one per weight the mock uses. Unlike the three-weight face
    /// this replaced, nothing here rounds: 600 is a real 600 and 800 is a real
    /// 800, which is what the `64 pt / 800` day counter needs to not look like
    /// a bold heading that grew.
    private static func postScriptName(for weight: Font.Weight) -> String {
        switch weight {
        case .heavy, .black: "\(familyName)-ExtraBold"
        case .bold: "\(familyName)-Bold"
        case .semibold: "\(familyName)-SemiBold"
        case .medium: "\(familyName)-Medium"
        default: "\(familyName)-Regular"
        }
    }

    /// True when every bundled cut actually registered. Read by a test and
    /// asserted at launch, so a dropped resource fails a build rather than a
    /// design review.
    static var fontsAreInstalled: Bool {
        ["Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]
            .allSatisfy { UIFont(name: "\(familyName)-\($0)", size: 12) != nil }
    }

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Surfaces

extension View {
    /// A card: `surface`, edged by a line, never lifted by a shadow.
    func wellieCard(
        color: Color = WellieTheme.surface,
        padding: CGFloat = 20,
        radius: CGFloat = WellieTheme.cardRadius
    ) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
    }

    /// A list card: rows supply their own vertical padding so the separators
    /// between them run the full width of the inset.
    func wellieListCard(color: Color = WellieTheme.surface) -> some View {
        self.padding(.horizontal, 20)
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
    }

    func wellieScreen() -> some View {
        foregroundStyle(WellieTheme.ink)
            .tint(WellieTheme.accent)
            .background(WellieTheme.background.ignoresSafeArea())
    }

    /// The scroll body every screen shares: one column of cards, inset from the
    /// edges.
    func wellieColumn() -> some View {
        self.padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 6)
            .padding(.bottom, 28)
    }
}

/// Meta: uppercased, tracked out, small, semibold.
///
/// The `9d` split used a second typeface to mean *this is data about the
/// thing*. The mock says the same thing with tracking — "DAYS LOGGED",
/// "RECENT PHOTOS", "15:12 · SNACK" — which is why this survived the change of
/// identity as a component rather than being deleted with the mono face. The
/// uppercasing and the tracking belong to the style; half a dozen call sites
/// had already inlined them once and were drifting a point apart.
struct WellieMeta: View {
    let text: String
    var size: CGFloat = 11
    var color: Color = WellieTheme.muted

    init(_ text: String, size: CGFloat = 11, color: Color = WellieTheme.muted) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(WellieTheme.metaFont(size))
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// A square avatar with an initial in it.
struct WellieAvatar: View {
    let name: String
    var side: CGFloat = 28

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }

    var body: some View {
        RoundedRectangle(cornerRadius: WellieTheme.thumbRadius, style: .continuous)
            .fill(WellieTheme.raised)
            .frame(width: side, height: side)
            .overlay {
                Text(initial)
                    .font(WellieTheme.font(side * 0.44, weight: .bold))
                    .foregroundStyle(WellieTheme.body)
            }
            .accessibilityLabel(name)
    }
}

/// A photograph that runs to the edge of the screen, or squares inside a card.
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
    /// The HIG minimum is about the finger, not the glyph, so the frame grows
    /// and the artwork does not — and `contentShape` is what makes the grown
    /// frame actually receive the tap rather than just occupy space.
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

    /// A meter or a bar filling to its value on appear.
    static func fill(_ reduced: Bool) -> Animation? {
        reduced ? nil : .easeOut(duration: 0.55)
    }
}

// MARK: - Buttons

/// The one filled button. Accent, page-coloured text, 24 pt.
struct WelliePrimaryButtonStyle: ButtonStyle {
    var enabled = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(16.5, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .foregroundStyle(enabled ? WellieTheme.onAccent : WellieTheme.muted)
            .background(
                (enabled ? WellieTheme.accent : WellieTheme.raised)
                    .opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The bordered one: a surface with a line round it, muted-bold label. The
/// mock's "Log another while this runs" and "From gallery" / "Camera" pair.
struct WellieSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WellieTheme.font(15, weight: .bold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(WellieTheme.body)
            .background(
                WellieTheme.surface.opacity(configuration.isPressed ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous)
                    .strokeBorder(WellieTheme.hairline, lineWidth: 1)
            }
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
            .padding(.vertical, 8)
            .contentShape(Rectangle())
    }
}

// MARK: - Text

struct WellieSectionTitle: View {
    let text: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(text)
                .font(WellieTheme.font(17, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            if let detail {
                Text(detail)
                    .font(WellieTheme.font(13.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
            .font(WellieTheme.font(size, weight: .regular))
            .foregroundStyle(WellieTheme.body)
            .lineSpacing(3)
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
            .font(WellieTheme.font(12.5, weight: .regular))
            .foregroundStyle(WellieTheme.muted)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Chips

/// The one chip in the app, in the three states the mock uses it in.
struct WellieChip: View {
    enum Style {
        /// A repeat, a food, a thing you might tap: surface fill, muted text.
        case soft
        /// The chosen option: accent fill, page-coloured text.
        case selected
        /// An option you have not taken.
        case outline
    }

    let text: String
    var style: Style = .soft
    var size: CGFloat = 13
    /// Take the whole width offered instead of hugging the text.
    ///
    /// The frame has to be inside the background, not around it: applied
    /// outside, the shape stays the width of its label and only the invisible
    /// layout box grows, which reads as three small chips adrift in a wide row.
    var fills = false

    var body: some View {
        Text(text)
            .font(WellieTheme.font(size, weight: style == .selected ? .bold : .semibold))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: fills ? .infinity : nil)
            .background(background, in: RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous))
            .overlay {
                if style != .selected {
                    RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
                        .strokeBorder(WellieTheme.hairline, lineWidth: 1)
                }
            }
    }

    private var foreground: Color {
        switch style {
        case .soft: WellieTheme.body
        case .selected: WellieTheme.onAccent
        case .outline: WellieTheme.muted
        }
    }

    private var background: Color {
        switch style {
        case .soft: WellieTheme.surface
        case .selected: WellieTheme.accent
        case .outline: WellieTheme.background
        }
    }
}

/// The mock's segmented row: `14 days / 30 days / 90 days`, and the meal
/// detail's `All of it / Half / A taste`. One selected chip, the rest outlined.
///
/// Not a `Picker`: the segmented style paints its own light chrome, and the
/// three options here are chips with a gap between them rather than cells in a
/// shared track.
struct WellieChipRow<Option: Hashable>: View {
    let options: [Option]
    @Binding var selection: Option
    let title: (Option) -> String
    /// Chips hug their text by default — the mock's day-window row. The share
    /// row on the meal detail divides the width in three instead.
    var fills = false

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    WellieChip(
                        text: title(option),
                        style: option == selection ? .selected : .soft,
                        size: 13.5,
                        fills: fills
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection ? [.isSelected, .isButton] : .isButton)
            }
            if !fills { Spacer(minLength: 0) }
        }
    }
}

// MARK: - Marks

/// A compact success or attention mark.
struct WellieMark: View {
    var isMet = true
    var size: CGFloat = 20

    var body: some View {
        Group {
            if isMet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(WellieTheme.onAccent, WellieTheme.accent)
            } else {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(WellieTheme.attention)
            }
        }
        .font(.system(size: size, weight: .semibold))
        .frame(width: size, height: size)
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
                    .font(WellieTheme.font(14.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(WellieTheme.faint)
        }
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }
}

/// A line between rows inside a card.
struct WellieRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(WellieTheme.hairline)
            .frame(height: 1)
    }
}
