import ShamanCore
import SwiftUI

/// Screen `10a`. The day as a document, not a conversation.
///
/// Everything underneath is unchanged — one composer, camera, voice, the same
/// four message states, the same queue. What changes is the reading: a rail down
/// the left with entries hanging off it, in the order the food was *eaten*.
///
/// That ordering is the whole idea, and it is a real departure. The thread sorts
/// by when a message was sent, deliberately: `Projection.thread(from:to:)`
/// explains that sorting by when a card was *ready* would let breakfast land
/// under an 11am photo simply because the photo was quicker. Eaten time is a
/// different axis and does not have that problem — it is stated by the person
/// and does not move once stated. So a meal logged at 19:02 and eaten at 08:12
/// slides into its morning slot with a quiet "logged 19:02" stamp, which is the
/// one thing a chat could never show: a day you wrote up at bedtime still reads
/// as the day you had.
///
/// A message still being read has no eaten time yet — nobody has told us when
/// it was — so it hangs at the bottom, next to now, and drops into place the
/// moment the reading lands.
struct DayTimeline: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var timeWidth = DayTimeline.timeWidth

    let turns: [ThreadTurn]
    let state: (ThreadTurn) -> LogMessageState
    let open: (MealEntry) -> Void
    let retry: (LogMessage) -> Void
    let delete: (ThreadTurn) -> Void

    private var calendar: Calendar { .current }

    var body: some View {
        // Computed once. `entries` maps and sorts, and reading it inside the
        // loop as `entries[index - 1]` re-ran the whole sort per row — O(n²)
        // per render pass on a view that redraws on every keystroke in the
        // composer below it.
        let rows = entries
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                TimelineEntry(
                    entry: entry,
                    gapAbove: index == 0 ? 0 : gap(from: rows[index - 1], to: entry),
                    isFirst: index == 0,
                    open: open,
                    retry: retry,
                    delete: delete
                )
            }
            nowMarker
        }
        .padding(.top, Self.leadIn)
    }

    /// Air above the first entry.
    ///
    /// The first row's `gapAbove` is zero — there is nothing above it to be
    /// spaced from — so without this the time, the dot and the dish name sat
    /// flush against the header's hairline, and the rail appeared to start
    /// mid-stroke. A day should open with a breath before the first thing that
    /// happened in it.
    static let leadIn: CGFloat = 18

    // MARK: - Order

    /// One thing that happened, at the time it happened.
    struct Entry: Identifiable {
        let id: UUID
        let turn: ThreadTurn
        let state: LogMessageState
        /// Where it sits on the rail. The meal's eaten time once there is a
        /// meal; the send time until then.
        let at: EpochMillis
        /// When it was written down, when that is meaningfully later than when
        /// it was eaten. Nil when they are the same moment, which is most
        /// meals — a stamp on every row would be noise rather than a fact.
        let loggedAt: EpochMillis?
    }

    /// The threshold for saying "logged later" out loud.
    ///
    /// Twenty minutes, because photographing a plate and getting the reading
    /// back is a couple of minutes and typing lunch up while the kettle boils is
    /// ten. Below this the two times are the same eating occasion described
    /// twice, and stamping it would make an ordinary log look like a correction.
    private static let laterThreshold: EpochMillis = 20 * 60 * 1000

    private var entries: [Entry] {
        turns.map { turn in
            let state = state(turn)
            let at = turn.meal?.eatenAt ?? turn.at
            let sent = turn.message?.sentAt ?? turn.at
            let later = sent - at >= Self.laterThreshold ? sent : nil
            return Entry(id: turn.id, turn: turn, state: state, at: at, loggedAt: later)
        }
        .sorted { $0.at == $1.at ? $0.id.uuidString < $1.id.uuidString : $0.at < $1.at }
    }

    /// Gaps between meals are visible as gaps.
    ///
    /// Proportional to the hours between them and then clamped hard: a literal
    /// scale would make a six-hour afternoon a screen and a half of nothing, and
    /// the point is not to measure the gap but to feel that there was one. Five
    /// hours between lunch and dinner should look different from twenty minutes
    /// between a coffee and a biscuit, and that is all.
    private func gap(from previous: Entry, to entry: Entry) -> CGFloat {
        let hours = Double(max(0, entry.at - previous.at)) / 3_600_000
        return min(56, max(10, CGFloat(hours) * 13))
    }

    // MARK: - Now

    /// The bottom of the rail. It is not an entry — nothing happened at it — so
    /// it gets a hollow tick and the time, and the rail stops there rather than
    /// running off the end of the day it has not reached yet.
    private var nowMarker: some View {
        HStack(alignment: .top, spacing: 0) {
            if !typeSize.isAccessibilitySize {
                Color.clear.frame(width: timeWidth)
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(WellieTheme.hairline)
                    .frame(width: 1, height: 18)
                Circle()
                    .strokeBorder(WellieTheme.faint, lineWidth: 1.5)
                    .frame(width: 7, height: 7)
            }
            .frame(width: DayTimeline.railWidth)

            WellieMeta("Now · \(Self.clock.string(from: Date()))")
                .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
    }

    /// The time column, right-aligned against the rail.
    ///
    /// Read through `@ScaledMetric` at the call site: at the large accessibility
    /// sizes an 11 pt mono "12:41" outgrows a fixed 46 pt and clips to "12:4".
    static let timeWidth: CGFloat = 46
    /// The rail itself: a hairline with a dot on it, and nothing else in the
    /// column so the dot cannot land under a label.
    static let railWidth: CGFloat = 20

    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter
    }()
}

// MARK: - One entry

/// A time on the rail, a dot, and whatever the app has made of it so far.
///
/// The four states from `7c` are unchanged; what moved is where they are drawn.
/// The rail carries the state — a filled dot for a meal, a hollow one for a
/// reading in progress, an orange one for a failure — so a day mid-read tells
/// you where it is without a pill having to say it twice.
private struct TimelineEntry: View {
    @Environment(AppModel.self) private var model
    /// The gutter grows with the reader's text size. At AX5 an 11 pt mono
    /// "12:41" is well past 46 pt and would clip to "12:4" — a timestamp that
    /// silently loses a digit is worse than one that wraps.
    @ScaledMetric(relativeTo: .caption2) private var timeWidth = DayTimeline.timeWidth
    @Environment(\.dynamicTypeSize) private var typeSize

    let entry: DayTimeline.Entry
    let gapAbove: CGFloat
    /// The first entry draws no rail above its dot: a line running up out of
    /// the first meal of the day points at nothing.
    var isFirst = false
    let open: (MealEntry) -> Void
    let retry: (LogMessage) -> Void
    let delete: (ThreadTurn) -> Void

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize { stacked } else { columns }
        }
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive) { delete(entry.turn) }
        }
        // The rail is a drawing of the day, not information — the time and the
        // meal are already spoken by the content. Merging the row into one
        // element also stops VoiceOver reading a bare "15:07" as its own stop.
        .accessibilityElement(children: .combine)
    }

    /// The ordinary reading: time in its own gutter, rail, entry.
    private var columns: some View {
        HStack(alignment: .top, spacing: 0) {
            // Three columns, and the time gets its own: drawn as an overlay on
            // the rail it sat on top of the dot, which is the one place on this
            // screen where two things must not share a pixel.
            time
                .padding(.top, gapAbove + 1)
                .frame(width: timeWidth, alignment: .trailing)

            rail

            content
                .padding(.top, gapAbove)
                .padding(.bottom, 4)
            Spacer(minLength: 0)
        }
    }

    /// At the accessibility sizes the gutter stops being a margin and becomes a
    /// column: scaled proportionally, a 46 pt time slot passes 130 pt and takes
    /// a third of the screen from the food. So the layout reflows — the time
    /// moves above the entry, the rail keeps its 20 pt, and the dish name gets
    /// the width back. The rail survives because it is what makes this a day
    /// rather than a list.
    private var stacked: some View {
        HStack(alignment: .top, spacing: 0) {
            rail
            VStack(alignment: .leading, spacing: 4) {
                time
                content
            }
            .padding(.top, gapAbove)
            .padding(.bottom, 8)
            Spacer(minLength: 0)
        }
    }

    private var time: some View {
        WellieMeta(DayTimeline.clock.string(from: Date(epochMillis: entry.at)))
    }

    // MARK: - The rail

    private var rail: some View {
        VStack(spacing: 0) {
            // The line runs the height of the gap above, so the rail is
            // continuous and the space between entries is *in* it rather than
            // beside it. A broken rail would read as a different day.
            Rectangle()
                .fill(WellieTheme.hairline)
                .frame(width: 1, height: gapAbove + 7)
                .opacity(isFirst ? 0 : 1)

            dot

            Rectangle()
                .fill(WellieTheme.hairline)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: DayTimeline.railWidth)
    }

    @ViewBuilder
    private var dot: some View {
        switch entry.state {
        case .logged:
            Circle().fill(WellieTheme.ink).frame(width: 7, height: 7)
        case .failed:
            Circle().fill(WellieTheme.attention).frame(width: 7, height: 7)
        case .sent, .reading:
            Circle()
                .strokeBorder(WellieTheme.blue, lineWidth: 1.5)
                .frame(width: 7, height: 7)
        }
    }

    // MARK: - The entry

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch entry.state {
            case .logged:
                if let meal = entry.turn.meal {
                    TimelineMealEntry(meal: meal, loggedAt: entry.loggedAt) { open(meal) }
                } else {
                    said
                }
            case .sent, .reading:
                said
                WellieMeta("Reading…", color: WellieTheme.blue)
            case .failed(let reason):
                said
                failed(reason)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, WellieTheme.screenInset)
    }

    /// What the person actually said, in their words, while there is nothing
    /// else to show. Once the reading lands the dish name replaces it — the
    /// sentence is not lost, it is on the meal.
    @ViewBuilder
    private var said: some View {
        if let text = entry.turn.message?.trimmedText {
            Text(text)
                .font(WellieTheme.font(15.5, weight: .medium))
                .foregroundStyle(WellieTheme.body)
                .fixedSize(horizontal: false, vertical: true)
        } else if entry.turn.message?.photoHash != nil {
            WellieMeta("Photo")
        }
    }

    private func failed(_ reason: String) -> some View {
        HStack(spacing: 10) {
            Text(reason)
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(WellieTheme.attention)
                .fixedSize(horizontal: false, vertical: true)
            if let message = entry.turn.message {
                Button("Retry") { retry(message) }
                    .font(WellieTheme.font(13, weight: .bold))
                    .foregroundStyle(WellieTheme.blue)
            }
        }
    }
}

/// A logged meal on the rail: name, what was in it, olives.
///
/// Flat rather than carded. A card inside a timeline draws a second boundary
/// around something the rail has already placed, and twenty of them turn the
/// day back into a list of objects — which is the reading `10a` exists to get
/// away from. The hairline underneath is the only separation it needs.
private struct TimelineMealEntry: View {
    @Environment(AppModel.self) private var model

    let meal: MealEntry
    let loggedAt: EpochMillis?
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(MealDisplay.title(meal))
                            .font(WellieTheme.font(16.5, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        WellieMeta(groups)

                        if let stamp {
                            // Quiet, and only when the two times genuinely
                            // differ: a day written up at bedtime should read
                            // as the day it was, with one small line admitting
                            // when it was written.
                            WellieMeta(stamp)
                        }
                    }
                    Spacer(minLength: 0)
                    if let image = PhotoStore.shared.thumbnail(for: meal.photoHash, side: 56) {
                        WelliePhoto(image: image, inCard: true)
                            .frame(width: 56, height: 56)
                    }
                }

                HStack(spacing: 10) {
                    OliveRow(olives: model.olives(for: meal).olives, size: 13)
                    if meal.eaten != .whole {
                        WellieMeta(meal.eaten.chipName)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The food groups, in the vocabulary a chip uses, capped at three. Mono
    /// caps because this is data about the meal rather than the meal.
    private var groups: String {
        var seen: [FoodGroup] = []
        for item in meal.items where !seen.contains(item.group) { seen.append(item.group) }
        return seen.prefix(3).map(\.shortName).joined(separator: ", ")
    }

    private var stamp: String? {
        loggedAt.map { "Logged \(DayTimeline.clock.string(from: Date(epochMillis: $0)))" }
    }
}
