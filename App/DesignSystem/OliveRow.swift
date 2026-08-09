import ShamanCore
import SwiftUI

/// One to five olives, filled.
///
/// The one place the design steps outside the blue palette. They are olive-green
/// because they are olives, and that is the whole justification — an olive drawn
/// in the accent blue is a progress dot, and a progress dot invites you to fill
/// it. These are a reading of a meal, not a target to hit.
///
/// Never labelled with a number beside it. `OliveRating.spelled` says "Three
/// olives" in the one place a headline is wanted; everywhere else the row is the
/// whole statement.
///
/// An unfilled olive is the same drawing at low opacity rather than an outline
/// or a grey one. Three reasons: it registers exactly against the filled olive,
/// where a separately drawn empty shape never quite would; it reads as "not this
/// far" rather than "disabled"; and it keeps the row from looking like a
/// progress bar with segments to complete.
struct OliveRow: View {
    let olives: Int
    var size: CGFloat = 16
    /// Proportional by default, so changing a size never leaves the row too
    /// tight or too loose and every use stays in the same rhythm.
    var spacing: CGFloat?

    private var gap: CGFloat { spacing ?? size * 0.34 }

    /// How much of the drawing survives in an unfilled slot. Low enough to be
    /// clearly unearned, high enough that five empties still read as a row of
    /// five rather than as blank space.
    private static let ghost = 0.17

    var body: some View {
        HStack(spacing: gap) {
            ForEach(1...OliveRating.range.upperBound, id: \.self) { step in
                OliveMark()
                    .frame(width: size, height: size)
                    .opacity(step <= olives ? 1 : Self.ghost)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(olives) of \(OliveRating.range.upperBound) olives")
    }
}

/// The olive, drawn rather than photographed.
///
/// The previous mark was a large raster emoji scaled to 16 pt — exactly the
/// size where photographic shading turns to mud, and where its ghost state
/// stopped reading as an olive at all. A flat shape is crisp at every size the
/// row is drawn at, needs no @2x/@3x renders, and the unfilled state really is
/// the same drawing at low opacity, as the row above promises.
private struct OliveMark: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                // Taller than it is wide, like the fruit; the frame stays
                // square so the row's rhythm is even regardless.
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.71, green: 0.76, blue: 0.28),
                                Color(red: 0.40, green: 0.48, blue: 0.12),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: w * 0.82, height: h)
                // One small specular dot is all the realism 16 pt can carry.
                Ellipse()
                    .fill(.white.opacity(0.45))
                    .frame(width: w * 0.22, height: h * 0.15)
                    .rotationEffect(.degrees(-32))
                    .offset(x: -w * 0.13, y: -h * 0.27)
            }
            .frame(width: w, height: h)
        }
    }
}
