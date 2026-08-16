import SwiftUI
import UIKit

/// Tokens sampled from the approved redesign — `App Redesign Final`, turn
/// `13`: *eatsome — the whole flow in one place*.
///
/// The app follows the phone. Every token below is a **pair**, and the one the
/// screen draws is whichever `userInterfaceStyle` is in force when it resolves.
/// That is a reversal of the previous rule — "dark, and only dark" — and the
/// reason it reversed is that "dark only" was never a design position, it was a
/// statement that only one half had been drawn. Both halves are drawn now, so
/// the app has no business overriding a system-wide preference a person set
/// once for every app on the device.
///
/// The two halves are the same design, not two designs:
///
/// - **Type.** Sora, 400–800, and it is the only face, in both schemes. The
///   mono-means-metadata rule is still gone: `WellieMeta` says *this is data
///   about the thing* with uppercasing and tracking rather than a second
///   typeface. One face is what lets a 23 pt figure and an 11 pt caption on the
///   same card read as one object.
/// - **Colour.** A page, two surfaces above it, and one periwinkle accent spent
///   on exactly three things: the primary button, a live value, and the current
///   selection. Olive survives as `protein`. Dark is a near-black page with
///   light on it; light is a warm off-white page with near-black on it — warm
///   rather than pure white, because a 100% white page beside a white card
///   leaves the card with nothing to be.
/// - **Contrast is checked per scheme, against that scheme's page.** `muted`
///   carries real words on every screen ("102 / 345–498 g", "Usually five to
///   eight seconds") so it clears 4.5:1 in both: `#737e92` is 4.75:1 on the dark
///   page, `#666e7e` is 4.54:1 on the light one. The accent darkens in light
///   mode for the same reason — the mock's `#8a97f7` takes white at 2.7:1 and
///   cannot carry a button label, where `#5462d2` takes it at 5.2:1 and is not
///   a different colour so much as the same one lit from the other side.
/// - **Shape.** Big radii, 14–26, shared by both schemes. These are the mock's
///   own numbers.
/// - **Surfaces.** `surface` on `background`, separated by a 1 pt `hairline`,
///   and still no shadows in either scheme. `wellieSurface` is that shape and
///   the only thing that draws it.
/// - **Photos.** Full-bleed and squared to `photoRadius` inside a card. The
///   meal detail screen runs one to the top edge under a gradient built from
///   `background`, so the gradient inverts with the page and the card still has
///   something to sit on.
///
/// One accent object per screen. `inkSurface`/`onInk` are the inversion pair
/// for anything that has to be the one contrasting block, and they swap ends
/// with the scheme.
enum WellieTheme {
    // MARK: - Colour
    //
    // Every value is an `adaptive` pair resolved against the trait collection,
    // so a screen written against these tokens is correct in both schemes
    // without knowing which one it is in. Reading `Environment(\.colorScheme)`
    // in a view to pick a colour is the thing this exists to prevent: it works
    // until the view is used inside something that overrides the scheme, and
    // then it is silently the wrong colour rather than a build error.

    /// The page. Warm off-white rather than white, so a white card is a card.
    static let background = adaptive(light: 0xF3F1EC, dark: 0x0B0D12)
    /// A card on the page. Everything with a border is this.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x13161E)
    /// Inputs, wells, and anything inset *inside* a card.
    static let well = adaptive(light: 0xF6F4EF, dark: 0x10131A)
    /// A raised fill: an unfilled meter, a secondary control, a bar in a chart
    /// that is not being pointed at.
    static let raised = adaptive(light: 0xE7E4DC, dark: 0x232834)

    /// Text.
    static let ink = adaptive(light: 0x151820, dark: 0xEEF1F7)
    /// Running prose — one step down from `ink`, still comfortably readable.
    static let body = adaptive(light: 0x474D5A, dark: 0xB4BDCC)
    /// Labels, captions, secondary values, every meta line.
    ///
    /// The floor is 4.5:1 **on that scheme's page**, and both values here were
    /// picked against it rather than derived from each other: `#737e92` is
    /// 4.75:1 on `#0b0d12`, `#666e7e` is 4.54:1 on `#f3f1ec`. The dark value is
    /// three steps lighter than the mock's `#6c7689`, which measures 4.26:1 and
    /// is under the floor for text this size.
    static let muted = adaptive(light: 0x666E7E, dark: 0x737E92)
    /// Chevrons, empty meter segments, the dim half of a fraction — **decoration
    /// and non-text marks only**: 1.5:1 on the light page, 1.6:1 on the dark
    /// one. The rule the old theme wrote down survives verbatim: if a thing has
    /// words in it, it does not get this colour. The exception is the trailing
    /// half of a large fraction, where the *figure* is the content, the
    /// denominator is scale, and it sits adjacent to its own bright numerator.
    static let faint = adaptive(light: 0xC7C9CF, dark: 0x3A4152)

    /// The one accent. Periwinkle, and the mock spends it on the primary
    /// button, the current selection, and a value that is alive right now.
    ///
    /// The light value is darker because `onAccent` inverts with it: the mock's
    /// `#8a97f7` under white text is 2.7:1, which no button label may be drawn
    /// at. `#5462d2` takes white at 5.2:1 and reads as the same periwinkle.
    static let accent = adaptive(light: 0x5462D2, dark: 0x8A97F7)
    /// Foreground on `accent`. The page colour on dark (7.3:1), white on light
    /// (5.2:1) — in both cases the thing the accent is *not*.
    static let onAccent = adaptive(light: 0xFFFFFF, dark: 0x0B0D12)

    /// The fill of an option a row is *currently set to*, among ones you could
    /// still tap: a surface washed toward the accent, under a 1 pt accent
    /// border and ink text.
    ///
    /// Deliberately quiet: a solid accent behind page-coloured text would be
    /// as loud as the figures above it, which are the answer the chip is only
    /// offering to change.
    ///
    /// A pair rather than one alpha over `surface`: the mock's `#171b28` is a
    /// low accent wash on a dark card, and the same alpha on a white card is
    /// very nearly invisible, so the light half is drawn stronger.
    static let selectedFill = adaptiveColor(light: accent.opacity(0.10), dark: color(0x171B28))

    /// Protein, and the only nutrient with a colour of its own.
    ///
    /// It gets one because it is the only one of the five with a *goal* rather
    /// than a reference range — see `DailyTargets.protein` — so a protein bar
    /// can honestly be full or short where an energy bar can only be long or
    /// less long.
    ///
    /// The light value is darkened to 4.5:1 because it is text in places, not
    /// only a bar — it was the ring and the duration on a workout row until
    /// those rows were cut, and it is still the figure on Progress.
    static let protein = adaptive(light: 0x68742A, dark: 0xA3B04A)
    /// A protein bar on a day that did not reach the goal.
    static let proteinDim = adaptive(light: 0xE5E8D2, dark: 0x2E331F)

    /// The one contrasting block, for anything that has to invert against the
    /// page. Swaps ends with the scheme.
    static let inkSurface = adaptive(light: 0x151820, dark: 0xE7EDF5)
    static let onInk = adaptive(light: 0xFFFFFF, dark: 0x0B0D12)

    static let attention = adaptive(light: 0x8F6212, dark: 0xE0A257)
    static let attentionSurface = adaptive(light: 0xF8EBD5, dark: 0x2A2113)
    static let danger = adaptive(light: 0xBB3B37, dark: 0xE27777)

    /// The line that does the work a shadow used to. One point, not a half: on
    /// a dark page a 0.5 pt line at 12% simply is not there.
    static let hairline = adaptive(light: 0xE6E2DA, dark: 0x1E2330)
    /// A slightly stronger line, for a control that has an edge and no fill.
    static let outline = adaptive(light: 0xD6D1C7, dark: 0x2A3040)

    // MARK: - Glass
    //
    // The floating tab shell and the meal detail's one translucent card are the
    // only places the app puts a surface *over* something — a scrolling page, a
    // photograph. They were written as `Color.white.opacity(…)` over
    // `.ultraThinMaterial`, which is the right instinct on a dark page and
    // invisible on a light one: white on white is nothing, and the capsule
    // loses its edge entirely. These four are the same construction with the
    // white swapped for the scheme's own contrasting end.

    /// Tint laid over `.ultraThinMaterial` to give a floating surface a body.
    static let glassFill = adaptiveColor(light: Color.white.opacity(0.7), dark: raised.opacity(0.56))
    /// The 1 pt edge on a floating surface.
    static let glassStroke = adaptiveColor(light: Color.black.opacity(0.08), dark: Color.white.opacity(0.14))
    /// The same edge, on the two controls that are their own object rather than
    /// a container: the round `+` and the stacked log button.
    static let glassStrokeStrong = adaptiveColor(light: Color.black.opacity(0.1), dark: Color.white.opacity(0.2))
    /// The selected tab's own fill inside the capsule.
    static let glassSelection = adaptiveColor(light: Color.black.opacity(0.07), dark: Color.white.opacity(0.13))

    /// The `+` beside the tabs, which is the one accent object in the shell.
    ///
    /// Solid on light and half-transparent on dark, which is not an
    /// inconsistency: on the dark page the material behind it is dark and the
    /// accent at 0.46 still reads as periwinkle, where on the light page the
    /// same 0.46 over near-white washes to lilac and the button stops being the
    /// brightest thing on the screen.
    static let glassAccentFill = adaptiveColor(light: accent, dark: accent.opacity(0.46))
    /// The glyph on `glassAccentFill`.
    static let onGlassAccent = adaptiveColor(light: onAccent, dark: ink)

    // MARK: - Shape

    static let screenInset: CGFloat = 20
    /// The mock's card. 22, and a 26 for the two that carry a photograph or a
    /// headline — see `heroRadius`.
    static let cardRadius: CGFloat = 22
    static let heroRadius: CGFloat = 26
    /// A control inside a card: a meter, a well, a tile.
    static let innerRadius: CGFloat = 20
    /// One entry in the day's timeline. Two points tighter than `innerRadius`
    /// because these are 52 pt tall and stacked four apart — at 20 the corners
    /// of adjacent rows very nearly touch and the column reads as a zip.
    static let rowRadius: CGFloat = 18
    /// 24, and it means *the widest thing on this screen*: the primary button,
    /// and the one card a screen exists to show — the meal detail's figures,
    /// a day's card in Earlier days. The mock draws all three at the same
    /// number, and giving the card a second name for 24 is how a design system
    /// ends up with two tokens that drift a point apart.
    static let controlRadius: CGFloat = 24
    /// The selected place inside the tab capsule. Its own number because the
    /// capsule it sits in is its own object: at `innerRadius` the pill's
    /// corners visibly disagree with the capsule around them.
    static let tabRadius: CGFloat = 23
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

    // MARK: - Resolving

    /// A colour that is two colours, resolved against whatever trait collection
    /// the view is drawn in.
    ///
    /// `UIColor(dynamicProvider:)` rather than an asset catalog pair or an
    /// `@Environment(\.colorScheme)` read at the call site. The environment
    /// read is the tempting one and it is wrong in a specific, quiet way: a
    /// view can be hosted somewhere that overrides the scheme — a sheet, a
    /// preview, a snapshot test, the share sheet's own chrome — and the
    /// environment value it captured no longer describes the pixels it is
    /// drawing on. A dynamic `UIColor` is resolved by UIKit at draw time, every
    /// time, so it cannot go stale.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        adaptiveColor(light: color(light), dark: color(dark))
    }

    /// The same, for pairs that are not opaque hexes — the translucent tints
    /// the floating shell lays over a material.
    private static func adaptiveColor(light: Color, dark: Color) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func color(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

// MARK: - Surfaces

extension View {
    /// A filled, rounded, edged block — and nothing about its insets.
    ///
    /// The one shape the whole app is made of: a fill, a continuous corner, a
    /// 1 pt line, never a shadow. It was written out by hand about twenty
    /// times, and the copies had begun to disagree — a `strokeBorder` here, a
    /// `stroke` there, one of them half a point.
    ///
    /// Padding is deliberately not its business. A card pads 20 all round, a
    /// list card pads its rows instead, a chip pads 16 by 10, and a stepper
    /// pads nothing at all; folding a default into the shape is what made the
    /// copies exist in the first place.
    func wellieSurface(
        _ color: Color = WellieTheme.surface,
        radius: CGFloat = WellieTheme.cardRadius,
        border: Color = WellieTheme.hairline,
        lineWidth: CGFloat = 1
    ) -> some View {
        background(color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(border, lineWidth: lineWidth)
            }
    }

    /// A card: `surface`, edged by a line, never lifted by a shadow.
    func wellieCard(
        color: Color = WellieTheme.surface,
        padding: CGFloat = 20,
        radius: CGFloat = WellieTheme.cardRadius
    ) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .wellieSurface(color, radius: radius)
    }

    func wellieScreen() -> some View {
        foregroundStyle(WellieTheme.ink)
            .tint(WellieTheme.accent)
            .background(WellieTheme.background.ignoresSafeArea())
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
