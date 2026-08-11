import ShamanCore
import SwiftUI

/// Screen `4a·5`. Progress.
///
/// Not called `ProgressView`, and not by accident: SwiftUI already owns that
/// name for the spinner, and a type shadowing it inside the app module turns
/// every `ProgressView()` in every other file into a compile error at best and
/// a blank rectangle at worst.
///
/// Two charts and two tiles. What is *not* here is as deliberate as what is:
/// there is no salt series, because a derived salt figure is a floor and a
/// trend line through fourteen floors would look exactly like a trend line
/// through fourteen measurements; and there is no rating, because the app
/// stopped scoring meals. What is left is the two figures a person actually
/// tracks — what they ate and whether they got their protein — and two facts.
struct ProgressScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var isTabRoot = false

    @State private var window = Window.twoWeeks

    enum Window: Int, CaseIterable, Hashable {
        case twoWeeks = 14
        case month = 30
        case quarter = 90

        var title: String { "\(rawValue) days" }
    }

    private var days: [AppModel.DayNutrition] { model.dailyNutrition(window.rawValue) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    WellieChipRow(options: Window.allCases, selection: $window, title: \.title)
                        .padding(.bottom, 4)
                    energyCard
                    proteinCard
                    tiles
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .background(WellieTheme.background)
        .toolbar(.hidden, for: .navigationBar)
        .wellieBackSwipe()
        .wellieScreen()
    }

    private var header: some View {
        ZStack {
            Text("Progress")
                .font(WellieTheme.font(16, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            if !isTabRoot {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 13, weight: .bold))
                            Text("Today")
                        }
                        .font(WellieTheme.font(14, weight: .semibold))
                        .foregroundStyle(WellieTheme.accent)
                        .wellieHitTarget()
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 18)
    }

    // MARK: - Energy

    private var energyCard: some View {
        let logged = days.filter(\.isLogged)
        return VStack(alignment: .leading, spacing: 0) {
            chartHeading(
                "Energy, kcal / day",
                value: logged.isEmpty ? "—" : Int(average(logged.map(\.kcal)).rounded()).formatted(),
                detail: logged.isEmpty ? nil : "avg"
            )

            BarSeries(
                values: days.map { $0.isLogged ? $0.kcal : nil },
                height: 84,
                // Today is the accent one, so the bar you are adding to is
                // findable in ninety of them.
                tint: { $0 == days.count - 1 ? WellieTheme.accent : WellieTheme.raised }
            )
            .padding(.top, 16)

            axis.padding(.top, 8)

            // The header figure is the average of the days that have something
            // on them, not of the window. Dividing by ninety when sixty of them
            // are blank reports a diet nobody was on — the app can only average
            // what it was told, and saying which days those were is the whole
            // difference between a figure and a claim.
            if !logged.isEmpty, logged.count < days.count {
                Text("Averaged over the \(logged.count) days you logged.")
                    .font(WellieTheme.font(12, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.top, 10)
            } else if logged.isEmpty {
                Text("Nothing logged in this window yet.")
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.top, 10)
            }
        }
        .wellieCard()
    }

    // MARK: - Protein

    /// The one nutrient with a goal, so the one chart that can be coloured.
    ///
    /// Energy has a reference *centre* and a ±10% band around it — a day at the
    /// top of that band is not a failure and a day at the bottom is not a win —
    /// so its bars stay grey. Protein has a floor you either cleared or did not.
    private var proteinCard: some View {
        let goal = model.dailyTargets?.protein
        let logged = days.filter(\.isLogged)
        let met = goal.map { target in logged.count { $0.protein >= target } } ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            chartHeading(
                "Protein, g / day",
                value: logged.isEmpty ? "—" : Int(average(logged.map(\.protein)).rounded()).formatted(),
                detail: goal.map { "avg · goal \(Int($0.rounded()))" } ?? "avg"
            )

            BarSeries(
                values: days.map { $0.isLogged ? $0.protein : nil },
                height: 64,
                tint: { index in
                    guard let goal else { return WellieTheme.raised }
                    return days[index].protein >= goal ? WellieTheme.protein : WellieTheme.proteinDim
                }
            )
            .padding(.top, 16)

            if let goal, !logged.isEmpty {
                Text("Green days hit \(Int(goal.rounded())) g — \(met) of \(logged.count) logged.")
                    .font(WellieTheme.font(12, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.top, 12)
            } else if goal == nil {
                Text("Add your body details in Settings and this gets a goal line.")
                    .font(WellieTheme.font(12, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.top, 12)
            }
        }
        .wellieCard()
    }

    // MARK: - Two facts

    private var tiles: some View {
        HStack(spacing: WellieTheme.cardSpacing) {
            tile(
                "Streak",
                value: "\(model.loggingStreak())",
                unit: "days",
                caption: nil
            )
            tile(
                "Weight, 30 d",
                value: weightChange.map { WeightFormat.value($0).formatted(.number.precision(.fractionLength(1))) } ?? "—",
                unit: weightChange == nil ? nil : WeightFormat.unit,
                // Health read access is by design indistinguishable from an
                // empty store, so this says what is true — there is no reading
                // here — rather than claiming access was refused.
                caption: weightChange == nil ? "No weight readings" : nil
            )
        }
    }

    private var weightChange: Double? { model.weightChange(overDays: 30) }

    private func tile(_ name: String, value: String, unit: String?, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(WellieTheme.font(13, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(WellieTheme.font(25, weight: .heavy))
                    .foregroundStyle(WellieTheme.ink)
                if let unit {
                    Text(unit)
                        .font(WellieTheme.font(13.5, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(WellieTheme.font(11.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieCard(padding: 18)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

    private func chartHeading(_ name: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(WellieTheme.font(13, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
            Spacer(minLength: 6)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(WellieTheme.font(15, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                if let detail {
                    Text(detail)
                        .font(WellieTheme.font(12, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    private var axis: some View {
        HStack {
            Text(days.first.map { $0.start.formatted(.dateTime.day().month(.abbreviated)) } ?? "")
            Spacer(minLength: 8)
            Text("today")
        }
        .font(WellieTheme.font(11, weight: .regular))
        .foregroundStyle(WellieTheme.faint)
    }

    private func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}

/// A row of bars, one per day, scaled to the tallest in the window.
///
/// Scaled to the data rather than to a target: these are two different
/// questions, and only the protein chart has a line worth being measured
/// against. A day with nothing logged is drawn as nothing at all rather than as
/// a zero-height bar, because a gap in the record and a day you ate nothing are
/// not the same fact and the chart must not merge them.
private struct BarSeries: View {
    /// Nil is a day with nothing on it. Deliberately not zero — see above.
    let values: [Double?]
    let height: CGFloat
    let tint: (Int) -> Color

    private var peak: Double { max(values.compactMap { $0 }.max() ?? 1, 1) }

    /// Ninety bars in three hundred points cannot each keep a five-point gap.
    private var spacing: CGFloat {
        switch values.count {
        case ...14: 5
        case ...30: 3
        default: 1.5
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(value == nil ? .clear : tint(index))
                    .frame(maxWidth: .infinity)
                    // A logged day always draws something: a 40 kcal coffee
                    // scaled against a 2,600 kcal peak is a bar half a point
                    // tall, which is indistinguishable from the gap it is meant
                    // to be different from.
                    .frame(height: value.map { max(3, height * $0 / peak) } ?? 0)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}
