import EatsomeCore
import SwiftUI

/// Screen `13g`. Progress: the trend, and the way to earlier days.
///
/// Two bar cards and one sentence. The energy card is the trend the
/// day is denominated in; the protein card is the one nutrient with a goal
/// rather than a range, drawn as the days that hit it and the days that did
/// not — the "green days" rule shown rather than stated. What is *not* here is
/// as deliberate: no salt series (no reference worth a line), no rating (the
/// app stopped scoring meals), and no sleep frame (it moved off this screen).
///
/// The empty state is not hidden; it is the point of the top row. The longer
/// windows are drawn locked, with the day they open beside them, and the
/// sentence at the bottom says how far in you are. A screen that greyed out
/// or vanished on day three would be telling a new person the app has nothing
/// for them, when what it has is a date to look forward to.
struct ProgressScreen: View {
    @Environment(EatsomeStore.self) private var store
    @Environment(\.mainTabContentClearance) private var clearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Back to Today. The shell owns which place is showing; this is how the
    /// mock's `‹ Today` asks it to change.
    var backToToday: (() -> Void)? = nil

    @State private var window = ProgressData.Window.fortnight
    @State private var showingEarlierDays = false

    private var data: ProgressData {
        ProgressData(projection: store.projection, window: window, targets: store.dailyTargets)
    }

    var body: some View {
        let data = data
        VStack(spacing: 0) {
            navRow
            ScrollView {
                VStack(spacing: 0) {
                    windowChips(data)
                        .padding(.top, 20)
                    TrendCard(
                        title: "Energy, kcal / day",
                        average: data.averageKcal,
                        averageSuffix: nil,
                        barHeight: 84,
                        days: data.days,
                        fraction: { data.fraction($0, of: \.kcal) },
                        tint: { _ in WellieTheme.raised },
                        footnote: energyFootnote(data)
                    )
                    .padding(.top, 18)
                    TrendCard(
                        title: "Protein, g / day",
                        average: data.averageProtein,
                        averageSuffix: data.proteinGoal.map { " · goal \(EatsomeFormat.whole($0))" },
                        barHeight: 64,
                        days: data.days,
                        fraction: { data.fraction($0, of: \.protein) },
                        tint: { day in proteinTint(day, goal: data.proteinGoal) },
                        footnote: proteinFootnote(data)
                    )
                    .padding(.top, 12)
                    honesty(data)
                        .padding(.top, 12)
                    earlierDaysRow
                        .padding(.top, 12)
                    Color.clear.frame(height: max(20, clearance))
                }
                .padding(.horizontal, WellieTheme.screenInset)
            }
            .scrollIndicators(.hidden)
        }
        .background(WellieTheme.background)
        .sheet(isPresented: $showingEarlierDays) {
            EarlierDaysSheet()
                .environment(store)
        }
        .wellieScreen()
    }

    // MARK: Top

    private var navRow: some View {
        HStack(spacing: 0) {
            Button {
                backToToday?()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    Text("Today")
                }
                .font(WellieTheme.font(14, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
            }
            .buttonStyle(.plain)
            .disabled(backToToday == nil)
            .frame(width: 80, alignment: .leading)
            .accessibilityLabel("Back to Today")

            Spacer(minLength: 0)
            Text("Progress")
                .font(WellieTheme.font(16, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            Spacer(minLength: 0)
            Color.clear.frame(width: 80, height: 1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }

    /// The selected window is a chip; a window that has not opened is drawn
    /// with a dashed outline and cannot be chosen, and the day it opens is
    /// written beside the row. Locked, not hidden.
    private func windowChips(_ data: ProgressData) -> some View {
        let nextLocked = ProgressData.Window.allCases.first { !data.openWindows.contains($0) }
        return HStack(spacing: 8) {
            ForEach(ProgressData.Window.allCases) { option in
                let open = data.openWindows.contains(option)
                Button {
                    window = option
                } label: {
                    Text(option.title)
                        .font(WellieTheme.font(13, weight: option == window ? .bold : .semibold))
                        .foregroundStyle(option == window ? WellieTheme.onInk : WellieTheme.muted)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            option == window ? WellieTheme.inkSurface : WellieTheme.well,
                            in: RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
                        )
                        .overlay {
                            if !open {
                                RoundedRectangle(cornerRadius: WellieTheme.chipRadius, style: .continuous)
                                    .strokeBorder(
                                        WellieTheme.raised,
                                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(!open)
                .accessibilityLabel(option.title)
                .accessibilityValue(open ? (option == window ? "Selected" : "") : "Opens on day \(option.rawValue)")
                .accessibilityAddTraits(option == window ? [.isSelected] : [])
            }
            if let nextLocked {
                Text("opens\nday \(nextLocked.rawValue)")
                    .font(WellieTheme.figure(11.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineSpacing(1.5)
                    .fixedSize()
                    .padding(.leading, 2)
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Cards

    private func energyFootnote(_ data: ProgressData) -> String {
        data.daysLogged == 0
            ? "Nothing to average yet."
            : "Averaged over the \(data.daysLogged) day\(data.daysLogged == 1 ? "" : "s") you logged."
    }

    private func proteinFootnote(_ data: ProgressData) -> String {
        guard let goal = data.proteinGoal else {
            return "Add your numbers on You and this shows which days hit your protein goal."
        }
        guard data.daysLogged > 0 else { return "Nothing to average yet." }
        // Only finished days are counted; today is still going and its bar
        // says so. "0 of the 0" is not a sentence, so until a day is finished
        // the footnote says what the rule is and leaves the count out.
        guard data.proteinDaysCompleted > 0 else {
            return "Green days hit \(EatsomeFormat.whole(goal)) g. Today is still going."
        }
        return "Green days hit \(EatsomeFormat.whole(goal)) g — \(data.proteinDaysHit) of the \(data.proteinDaysCompleted) you logged."
    }

    private func proteinTint(_ day: ProgressData.Day, goal: Double?) -> Color {
        guard let goal, let protein = day.nutrients?.protein else { return WellieTheme.raised }
        return protein >= goal ? WellieTheme.protein : WellieTheme.proteinDim
    }

    // The two tiles that sat here are gone, for two different reasons.
    //
    // *Weight, since start* printed a dash and always would have: the profile
    // keeps one figure, not a history, and nothing writes a second one. A tile
    // that can only ever say "—" is a promise the app has no way to keep.
    //
    // *Streak* could be computed and was accurate, and that is not the same as
    // being worth drawing. `6 / 90 days` on Today counts days logged, which is
    // a record; a streak counts days logged *in a row*, which is a score, and
    // it is the one figure on this screen that would have got worse because of
    // something you did rather than something you ate.

    private func honesty(_ data: ProgressData) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Circle()
                .strokeBorder(WellieTheme.protein, lineWidth: 1.5)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(data.honesty)
                .font(WellieTheme.font(12.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .wellieSurface(WellieTheme.well)
    }

    private var earlierDaysRow: some View {
        Button { showingEarlierDays = true } label: {
            WellieChevronRow(title: "Earlier days", value: nil, verticalPadding: 14)
                .padding(.horizontal, 18)
                .wellieSurface()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens each earlier day as a card")
    }
}

// MARK: - The trend card

/// One bar per day in the window, drawn to the window's own scale.
///
/// A day before you started is a four-point stub in the hairline colour: not
/// a small bar, a place where a bar would go. A logged day is a bar. Today is
/// the accent, because it is the one day still moving. There is no line and no
/// smoothing — fourteen bars are fourteen facts, and a curve through them
/// would be a fifteenth thing the app made up.
private struct TrendCard: View {
    let title: String
    let average: Double?
    let averageSuffix: String?
    let barHeight: CGFloat
    let days: [ProgressData.Day]
    let fraction: (ProgressData.Day) -> Double?
    let tint: (ProgressData.Day) -> Color
    let footnote: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Text(title)
                    .font(WellieTheme.font(12.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                    .lineLimit(1)
                    .padding(.trailing, 132)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(average.map(EatsomeFormat.whole) ?? "—")
                        .font(WellieTheme.figure(19, weight: .heavy))
                        .foregroundStyle(WellieTheme.ink)
                    Text(" avg\(averageSuffix ?? "")")
                        .font(WellieTheme.font(11.5, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenHeader)

            bars
                .frame(height: barHeight)
                .padding(.top, 16)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenBars)

            axis
                .padding(.top, 8)

            Text(footnote)
                .font(WellieTheme.font(12, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieSurface()
        .onAppear { withAnimation(WellieMotion.fill(reduceMotion)) { filled = true } }
    }

    private var bars: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(days) { day in
                let height = fraction(day)
                RoundedRectangle(cornerRadius: height == nil ? 2 : 4, style: .continuous)
                    .fill(day.isToday && height != nil ? WellieTheme.accent : (height == nil ? WellieTheme.hairline : tint(day)))
                    .frame(height: height.map { max(4, barHeight * ($0 * (filled ? 1 : 0))) } ?? 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    /// The left end says what the first bar is: either the day the window
    /// starts, or that it is a day before anything was logged.
    private var axis: some View {
        HStack {
            Text(leftLabel)
            Spacer(minLength: 8)
            Text("today")
        }
        .font(WellieTheme.font(11.5, weight: .regular))
        .foregroundStyle(WellieTheme.muted)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private var leftLabel: String {
        guard let first = days.first else { return "" }
        let date = first.date.formatted(.dateTime.day().month(.abbreviated))
        return first.beforeStart ? "\(date) · before you started" : date
    }

    private var spokenHeader: String {
        let value = average.map(EatsomeFormat.whole) ?? "no average yet"
        return "\(title): \(value) average\(averageSuffix ?? "")"
    }

    private var spokenBars: String {
        let logged = days.filter(\.logged).count
        let before = days.filter(\.beforeStart).count
        var parts = ["\(days.count) days, \(logged) logged"]
        if before > 0 { parts.append("\(before) before you started") }
        return parts.joined(separator: ", ")
    }
}
