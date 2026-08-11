import ShamanCore
import SwiftUI

/// Screen `4a·1`. Today, and the app's home.
///
/// This replaced the thread. The thread put the composer permanently on screen
/// and made the day a conversation, which was right while logging was the only
/// thing the app did — but a conversation has no top, and the two questions
/// people actually open the app with ("am I keeping this up?" and "how much
/// have I had today?") were both answered somewhere below the fold, if at all.
/// So the day is a page again: a counter, a week, four figures, and what you
/// ate. Logging and the other top-level sections now live in `MainTabView`.
///
/// The counter leads because it is the one figure that is unambiguously good
/// news. It counts *days logged*, not a score: the app can see what it was
/// told about and nothing else, and a number that dimmed because of what you
/// ate would turn a record into a report card. The olive rating that used to
/// sit here is gone for exactly that reason.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var showingProfile = false
    @State private var openMeal: MealEntry?
    @State private var showingHistory = false
    @State private var openDay: DayLog?
    @State private var mealPendingRemoval: MealEntry?

    private var meals: [MealEntry] { model.mealsToday() }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: WellieTheme.cardSpacing) {
                        counter
                        week
                        NutrientCard(
                            total: model.nutrientsToday,
                            targets: model.dailyTargets,
                            onSetUp: { showingProfile = true }
                        )
                        mealList
                    }
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
            }
            .background(WellieTheme.background)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openMeal) {
                MealDetailView(meal: $0)
                    .hidesMainTabBar()
            }
            .sheet(isPresented: $showingHistory) { HistoryView() }
            .sheet(item: $openDay) { DaySheet(day: $0.start) }
            .sheet(isPresented: $showingProfile) { NutritionProfileSettingsView() }
            .confirmationDialog(
                "Remove this meal?",
                isPresented: removalConfirmationPresented,
                titleVisibility: .visible
            ) {
                if let meal = mealPendingRemoval {
                    Button("Remove", role: .destructive) {
                        mealPendingRemoval = nil
                        Task { await model.deleteMeal(meal) }
                    }
                }
                Button("Cancel", role: .cancel) { mealPendingRemoval = nil }
            } message: {
                Text("It leaves your history. The photo goes with it.")
            }
        }
        .wellieScreen()
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshHealth() }
            // Polling on open, which is the whole of the freshness story until
            // push exists.
            Task { await model.synchronizeAccount() }
        }
    }

    private var removalConfirmationPresented: Binding<Bool> {
        Binding(
            get: { mealPendingRemoval != nil },
            set: { shown in
                if !shown { mealPendingRemoval = nil }
            }
        )
    }

    // MARK: - Header

    /// Tables, Progress, and settings have permanent places in the tab shell,
    /// so the day header can be only the day. The small calendar mark keeps the
    /// full history reachable after removing the old `Earlier days` footer.
    private var header: some View {
        Button { showingHistory = true } label: {
            HStack(spacing: 6) {
                Text(DayFormat.long(Date()))
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .semibold))
            }
            .font(WellieTheme.font(14, weight: .regular))
            .foregroundStyle(WellieTheme.muted)
            .wellieHitTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open meal history, \(DayFormat.long(Date()))")
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }

    // MARK: - The counter

    /// `6 / 90`, and the denominator is deliberately the quieter half.
    ///
    /// `faint` is decoration-only everywhere else in this app because it is
    /// 1.6:1 on the page. The exception is here and it is argued rather than
    /// assumed: the denominator is 42 pt, sits against its own bright numerator,
    /// and the accessibility label below reads the whole fraction aloud, so
    /// nothing about the figure depends on resolving that grey.
    private var counter: some View {
        let logged = model.daysLogged()
        return VStack(spacing: 4) {
            WellieMeta("Days logged")
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("\(logged)")
                    .font(WellieTheme.font(58, weight: .heavy))
                    .foregroundStyle(WellieTheme.ink)
                Text(" / \(AppModel.loggingWindow)")
                    .font(WellieTheme.font(42, weight: .heavy))
                    .foregroundStyle(WellieTheme.faint)
            }
            .tracking(-1.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(logged) of the last \(AppModel.loggingWindow) days logged")
    }

    // MARK: - The week

    /// Seven days ending today. Filled means something was written down.
    private var week: some View {
        HStack(spacing: 0) {
            ForEach(model.recentDays(7).reversed()) { day in
                DayDot(day: day) { openDay = day }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 6)
    }

    // MARK: - What you ate

    @ViewBuilder
    private var mealList: some View {
        if meals.isEmpty {
            VStack(spacing: 6) {
                Text("Nothing logged yet today.")
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(WellieTheme.body)
                Text("Tell it what you ate, or show it.")
                    .font(WellieTheme.font(13.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
        } else {
            ForEach(meals) { meal in
                SwipeToRemove(onRemove: { mealPendingRemoval = meal }) {
                    Button { openMeal = meal } label: { MealRow(meal: meal) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

}

// MARK: - One day in the week strip

private struct DayDot: View {
    let day: DayLog
    let open: () -> Void

    private var isToday: Bool { Calendar.current.isDateInToday(day.start) }

    private var initial: String {
        String(day.start.formatted(.dateTime.weekday(.abbreviated)).prefix(1))
    }

    var body: some View {
        Button(action: open) {
            Text(initial)
                .font(WellieTheme.font(12, weight: .bold))
                .foregroundStyle(day.isLogged ? WellieTheme.onAccent : WellieTheme.muted)
                .frame(width: 32, height: 32)
                .background {
                    Circle().fill(day.isLogged ? WellieTheme.accent : WellieTheme.raised)
                }
                .overlay {
                    // Today, before anything has been logged, is an outline rather
                    // than an empty dot: the day is not a gap yet.
                    if isToday && !day.isLogged {
                        Circle().strokeBorder(WellieTheme.accent, lineWidth: 2)
                    }
                }
        }
        .buttonStyle(.plain)
        .wellieHitTarget()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Open \(DayFormat.title(day.start)), \(day.isLogged ? Count.meals(day.mealCount).lowercased() : "nothing logged")"
        )
    }
}

// MARK: - The four figures

/// Energy, protein, carbohydrate, fat — against the day's references.
///
/// Salt is the one of the five that is *not* here, and its absence is the
/// invariant rather than an oversight: `Nutrients.saltGrams` is the salt in the
/// food and a known floor, because cooking salt carries no weight on the plate.
/// Drawn as a meter against `DailyTargets.salt` it would read "well under" on a
/// four-gram lunch — a confident, complete-looking, wrong number, which is the
/// exact failure this whole design is arranged against. It stays on the meal
/// detail, where it is printed as `≥` with no ceiling beside it.
private struct NutrientCard: View {
    let total: NutrientTotal
    let targets: DailyTargets?
    let onSetUp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            NutrientMeter(
                name: "Energy",
                value: total.nutrients.kcal,
                target: targets.map { .point($0.kcal) },
                unit: "kcal",
                tint: WellieTheme.accent
            )
            NutrientMeter(
                name: "Protein",
                value: total.nutrients.protein,
                target: targets.map { .point($0.protein) },
                unit: "g",
                tint: WellieTheme.protein
            )
            NutrientMeter(
                name: "Carbs",
                value: total.nutrients.carbohydrate,
                target: targets.map { .band($0.carbohydrateRange) },
                unit: "g",
                tint: WellieTheme.accent
            )
            NutrientMeter(
                name: "Fat",
                value: total.nutrients.fat,
                target: targets.map { .band($0.fatRange) },
                unit: "g",
                tint: WellieTheme.accent
            )

            if targets == nil {
                Button(action: onSetUp) {
                    HStack(spacing: 6) {
                        Text("Add your body details for daily references")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
                    }
                    .font(WellieTheme.font(13, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else if !total.isComplete {
                // A day totalled from the part of the plate that resolved is
                // not a small error, it is a different number wearing the same
                // label — and unlike a missing figure it is invisible. Every
                // screen showing a total has to surface this.
                Text("\(Int(total.unresolvedGrams.rounded())) g today wasn't recognised, so these are short by it.")
                    .font(WellieTheme.font(12, weight: .regular))
                    .foregroundStyle(WellieTheme.attention)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .wellieCard(padding: 20)
    }
}

/// One labelled meter.
///
/// Two kinds of target, because the science publishes two kinds. Energy and
/// protein have a *number* — `DailyTargets.kcal` and `.protein` — so they get a
/// denominator. Carbohydrate and fat have an AMDR *range*, and `DailyTargets`
/// deliberately declines to collapse one into a single figure, because picking
/// a point inside 45–65% is a preference the source does not contain. So the
/// band is drawn as a band: a lighter stretch of track between the two bounds,
/// with the day's fill on top of it.
private struct NutrientMeter: View {
    enum Target {
        case point(Double)
        case band(ClosedRange<Double>)

        var upper: Double {
            switch self {
            case .point(let value): value
            case .band(let range): range.upperBound
            }
        }
    }

    let name: String
    let value: Double
    let target: Target?
    let unit: String
    var tint: Color = WellieTheme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    /// What the full width of the track is worth.
    ///
    /// `max(target, value)` rather than the target alone, so a day that goes
    /// past its reference is drawn as going past it — a bar pinned at 100%
    /// makes 3,000 kcal and 1,800 kcal look like the same day. Under the
    /// reference, which is the common case and the one the mock draws, this is
    /// exactly the target.
    private var scale: Double {
        max(target?.upper ?? value, value, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                Spacer(minLength: 6)
                Text(valueText)
                    .font(WellieTheme.font(13.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(WellieTheme.hairline)

                    if case .band(let range) = target {
                        Capsule()
                            .fill(WellieTheme.raised)
                            .frame(width: width * (range.upperBound - range.lowerBound) / scale)
                            .offset(x: width * range.lowerBound / scale)
                    }

                    Capsule()
                        .fill(tint)
                        .frame(width: max(0, width * (hasAppeared ? value : 0) / scale))

                    // Only visible when the day has gone past the reference —
                    // otherwise it sits exactly under the end of the fill.
                    if value > (target?.upper ?? .infinity) {
                        Capsule()
                            .fill(WellieTheme.background)
                            .frame(width: 2)
                            .offset(x: width * (target?.upper ?? 0) / scale - 1)
                    }
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(WellieMotion.fill(reduceMotion)) { hasAppeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(valueText)")
    }

    private var valueText: String {
        let amount = Int(value.rounded()).formatted()
        guard let target else { return "\(amount) \(unit)" }
        switch target {
        case .point(let goal):
            return "\(amount) / \(Int(goal.rounded()).formatted()) \(unit)"
        case .band(let range):
            return "\(amount) / \(Int(range.lowerBound.rounded()).formatted())–"
                + "\(Int(range.upperBound.rounded()).formatted()) \(unit)"
        }
    }
}

// MARK: - One meal

/// The thumbnail, what it was, and what it came to.
///
/// The second line is the two figures a person actually recognises a meal by —
/// its energy and its protein — rather than the food groups the old card
/// listed. Absent when nothing resolved, because "0 kcal · 0 g protein" under a
/// photograph of dinner is a worse answer than saying nothing.
struct MealRow: View {
    @Environment(AppModel.self) private var model
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 14) {
            MealThumbnail(meal: meal, side: 56, radius: WellieTheme.thumbRadius)
            VStack(alignment: .leading, spacing: 3) {
                Text(MealDisplay.title(meal))
                    .font(WellieTheme.font(16, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(WellieTheme.font(13, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WellieTheme.faint)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WellieTheme.surface, in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [DayFormat.time(meal.eatenAt)]
        let total = model.nutrients(in: meal).nutrients
        if total.kcal.rounded() > 0 { parts.append("\(Int(total.kcal.rounded())) kcal") }
        if total.protein.rounded() > 0 { parts.append("\(Int(total.protein.rounded())) g protein") }
        if meal.eaten != .whole { parts.append(meal.eaten.chipName.lowercased()) }
        return parts.joined(separator: " · ")
    }
}
