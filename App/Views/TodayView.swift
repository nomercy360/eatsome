import ShamanCore
import SwiftUI

/// Today, as screen `1b` of the approved redesign, with `2b`'s empty states.
///
/// The number stopped being the headline. A row of seven dots carries the
/// rolling window visibly — which is what the window actually is — and the
/// sentence above it does the judging in words. On a thin week there is no
/// score at all: the app's own rule is that a few days cannot be scored, and
/// printing a figure and then explaining underneath that it means nothing is
/// the wrong way round.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    @State private var showingSettings = false
    @State private var showingHistory = false
    @State private var openDay: DayLog?
    /// The empty state runs its own capture sheet. The camera tab presents one
    /// from the root, but the tab is a sibling of this view rather than
    /// something it can reach — and a card headed "Photograph your first meal"
    /// has to be able to do that itself.
    @State private var capturing = false

    private var meals: [MealEntry] { model.mealsToday() }
    private var days: [DayLog] { model.weekDays() }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: WellieTheme.cardSpacing) {
                    weekHero

                    if meals.isEmpty && model.projection.meals.isEmpty {
                        firstMealCard
                    } else {
                        todayCard
                    }

                    if !meals.isEmpty { mealsCard }

                    healthCard

                    if let error = model.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.danger)
                            .wellieCard()
                    }
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle("eatsome")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refreshHealth() }
            .sheet(isPresented: $capturing) { MealCaptureView() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingHistory = true } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Earlier days")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingHistory) { HistoryView() }
            .navigationDestination(item: $openDay) { DayView(day: $0.start) }
        }
        .wellieScreen()
    }

    // MARK: - The week

    private var weekHero: some View {
        let result = model.adherence()
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(WellieTheme.font(13, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                Text(headline(result))
                    .font(WellieTheme.font(27, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WellieWeekDots(days: dots, behind: WellieTheme.ice) { id in
                openDay = days.first { $0.id == id }
            }

            WellieProse(caption(result))
        }
        .wellieCard(color: WellieTheme.ice, padding: 24)
    }

    private var dots: [WellieWeekDots.Day] {
        let calendar = Calendar.current
        return days.map {
            .init(
                id: $0.id,
                initials: DayFormat.initials($0.start, calendar: calendar),
                fill: $0.fill,
                isToday: calendar.isDateInToday($0.start)
            )
        }
    }

    /// Four states, and the order matters: nothing logged, too thin to score,
    /// on track, taking shape.
    private func headline(_ result: MedasResult) -> String {
        if result.daysLogged == 0 { return "Let's start with\none meal." }
        if result.isUnderreported {
            return "\(Count.spell(result.daysLogged)) day\(result.daysLogged == 1 ? "" : "s") in.\nKeep going."
        }
        return result.meetsGoodAdherence ? "You're eating\nMediterranean." : "Your week is\ntaking shape."
    }

    private func caption(_ result: MedasResult) -> String {
        if result.daysLogged == 0 {
            return """
            Your week fills in as you go. Nothing is scored until there are a few days to \
            look at — a quiet Tuesday isn't a failure.
            """
        }
        if result.isUnderreported {
            return """
            \(Count.spell(result.daysLogged)) of \(Count.spell(result.windowDays, capitalized: false)) days. \
            A couple more and there's enough here to tell you something true about your week.
            """
        }

        let logged = """
        \(Count.spell(result.daysLogged)) of the last \
        \(Count.spell(result.windowDays, capitalized: false)) days logged.
        """
        guard let missing = missingFoods else { return logged }
        return "\(logged) \(missing) what the week is missing."
    }

    /// The two weekly targets furthest from being met, named as food.
    private var missingFoods: String? {
        let weekly = Set(Medas.items.compactMap { item -> Int? in
            if case .weeklyAtLeast = item.rule { return item.id }
            return nil
        })
        let names = model.adherence().items
            .filter { weekly.contains($0.id) && !$0.passed }
            .sorted { ($0.observed / max($0.target, 1)) < ($1.observed / max($1.target, 1)) }
            .compactMap { MedasCopy.foodNoun($0.id) }
            .prefix(2)

        switch names.count {
        case 0: return nil
        case 1: return "\(names[0].capitalizedFirst) is"
        default: return "\(names[0].capitalizedFirst) and \(names[1]) are"
        }
    }

    // MARK: - Today

    /// Day one. The app asks for exactly one thing, and offers the two ways to
    /// give it.
    private var firstMealCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(text: "Photograph your first meal")
            WellieProse("Breakfast, a snack, whatever is next. It takes about ten seconds.")

            // Without this the card asks for a photograph and offers only the
            // other way of doing it — "or add it by hand" reading as the
            // alternative to a button that was never on the card. The camera is
            // in the tab bar, but day one is the moment you are least likely to
            // know that.
            Button("Photograph a meal") { capturing = true }
                .buttonStyle(WelliePrimaryButtonStyle())
                .padding(.top, 2)

            NavigationLink { AddByHandView(day: Date()) } label: {
                Text("or add it by hand")
                    .font(WellieTheme.font(14.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.blue)
            }
            .padding(.top, 2)
        }
        .wellieCard()
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            WellieSectionTitle(text: "Today you've had")

            if eatenGroups.isEmpty {
                WellieProse("Nothing yet today.")
            } else {
                FlowLayout(spacing: 7, lineSpacing: 7) {
                    ForEach(eatenGroups, id: \.self) { WellieChip(text: $0.shortName) }
                    if let nudge = todayNudge {
                        WellieChip(text: nudge, style: .outline)
                    }
                }
            }

            proteinRow
        }
        .wellieCard()
    }

    private var eatenGroups: [FoodGroup] {
        var seen = Set<FoodGroup>()
        return meals.flatMap(\.items).map(\.group).filter { seen.insert($0).inserted }
    }

    /// One thing that would round the day off, phrased as an addition rather
    /// than a deficit: "+ fruit again", not "Fruit 1/3".
    private var todayNudge: String? {
        let excluded = model.config.medas.excludedItems
        let today = meals
        for item in Medas.items where !excluded.contains(item.id) {
            guard case .dailyAtLeast(let groups, let target) = item.rule else { continue }
            let observed = groups.reduce(0.0) { total, group in
                total + today.reduce(0) { $0 + $1.servings(of: group) }
            }
            guard observed < target, let group = groups.first else { continue }
            return observed > 0 ? "+ \(group.sentenceName) again" : "+ \(group.sentenceName)"
        }
        return nil
    }

    /// The day in five figures, protein first.
    ///
    /// Protein keeps the meter because it is the only one of the five that is a
    /// floor — a number to reach, where the rest are ranges to sit inside and
    /// salt is a ceiling. Drawing four more meters would say they were all the
    /// same kind of thing and invite eating to each of them, so the other four
    /// are stated next to their target and left alone.
    private var proteinRow: some View {
        let total = model.nutrientsToday
        let day = total.nutrients
        let targets = model.dailyTargets
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Protein")
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                    Text("\(Int(day.protein.rounded())) g")
                        .font(WellieTheme.font(19, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                }

                if let target = targets?.protein {
                    WellieMeter(fraction: day.protein / max(target, 1), height: 6)
                    Text("of \(Int(target))")
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                } else {
                    Text("A weight from Health sets the target.")
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Divider().overlay(WellieTheme.hairline)

            HStack(alignment: .top, spacing: 0) {
                figureCell("Energy", "\(Int(day.kcal.rounded()))", "kcal",
                           of: targets.map { "\(Int($0.kcal))" })
                figureCell("Carbs", "\(Int(day.carbohydrate.rounded()))", "g",
                           of: targets.map { "\(Int($0.carbohydrate))" })
                figureCell("Fat", "\(Int(day.fat.rounded()))", "g",
                           of: targets.map { "\(Int($0.fat))" })
                // No target beside salt, deliberately. The derived figure is a
                // floor — composition tables publish unsalted preparations, and
                // measured against a canteen meal that printed 4 g this reads
                // 0.7 — so putting "of 5" next to it would turn a known
                // undercount into a reassurance. `Nutrients.saltGrams` has the
                // measurement. What the caption says instead is what is true.
                figureCell("Salt",
                           (total.saltIsFloor ? "≥ " : "") + String(format: "%.1f", day.saltGrams),
                           "g", of: nil)
            }

            if total.saltIsFloor {
                Text("Salt is what the food tables know about; cooking adds more.")
                    .font(WellieTheme.font(11, weight: .medium))
                    .foregroundStyle(WellieTheme.faint)
            }

            if !total.isComplete {
                // Said out loud rather than swallowed. A total quietly short by
                // the weight of an unrecognised dish is the exact failure this
                // app refused to ship for three years, and the fix is one tap
                // away: name the food and it resolves.
                Text("\(Int(total.unresolvedGrams.rounded())) g not recognised — "
                     + "these figures are short by whatever it was.")
                    .font(WellieTheme.font(12, weight: .medium))
                    .foregroundStyle(WellieTheme.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
    }

    private func figureCell(
        _ name: String,
        _ value: String,
        _ unit: String,
        of target: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(WellieTheme.font(11.5, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(WellieTheme.font(16, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                Text(unit)
                    .font(WellieTheme.font(11, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
            }
            if let target {
                Text("of \(target)")
                    .font(WellieTheme.font(11, weight: .medium))
                    .foregroundStyle(WellieTheme.faint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Meals

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(Count.meals(meals.count))
                    .font(WellieTheme.font(17, weight: .bold))
                Spacer()
                Text("swipe a meal to remove")
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }

            ForEach(meals) { meal in
                SwipeToRemove {
                    Task { await model.deleteMeal(meal) }
                } content: {
                    NavigationLink { MealDetailView(meal: meal) } label: {
                        MealRow(meal: meal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .wellieCard()
    }

    // MARK: - Health

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("From Apple Health")
                    .font(WellieTheme.font(17, weight: .bold))
                Spacer()
                if model.isLoadingHealth { ProgressView().controlSize(.small) }
            }

            if !model.hasRequestedHealthAccess {
                WellieProse(
                    """
                    Sleep, workouts and weight can appear here. Your weight is also what \
                    sets a protein target.
                    """
                )
                Button("Connect Apple Health") { Task { await model.connectHealth() } }
                    .buttonStyle(WellieSecondaryButtonStyle())
            } else {
                HStack(alignment: .top, spacing: 10) {
                    HealthTile(
                        icon: "moon.fill",
                        label: "Sleep",
                        value: model.latestSleep.map { DayFormat.duration($0.asleep) } ?? "None",
                        delta: model.sleepDeltaAgainstAverage.map {
                            Delta(text: DayFormat.duration(abs($0)), isUp: $0 >= 0, caption: "vs your average")
                        }
                    )
                    HealthTile(
                        icon: "figure.run",
                        label: "Workouts",
                        value: "\(model.workoutCount(weeksAgo: 0))",
                        delta: workoutDelta
                    )
                    HealthTile(
                        icon: "scalemass.fill",
                        label: "Weight",
                        value: model.latestWeight.map { WeightFormat.string($0.kilograms) } ?? "None",
                        // Kilograms, not per cent: a percentage of a body weight
                        // is a number nobody has an instinct for.
                        delta: model.weightDelta.map {
                            Delta(
                                text: "\(WeightFormat.value(abs($0)).formatted(.number.precision(.fractionLength(1)))) \(WeightFormat.unit)",
                                isUp: $0 >= 0,
                                caption: "since last"
                            )
                        }
                    )
                }

                if model.healthIsEmpty {
                    // The invariant, surfaced: iOS makes a refused read look
                    // exactly like an empty store, so the app must not claim it
                    // knows which one this is.
                    WellieCaption(
                        """
                        No samples. Either nothing is recorded, or Health access was declined — \
                        iOS does not tell apps which.
                        """
                    )
                }
            }

            if let error = model.healthError {
                Text(error)
                    .font(WellieTheme.font(12, weight: .medium))
                    .foregroundStyle(WellieTheme.attention)
            }
        }
        .wellieCard(color: WellieTheme.ice)
    }

    private var workoutDelta: Delta? {
        let previous = model.workoutCount(weeksAgo: 1)
        let change = model.workoutCount(weeksAgo: 0) - previous
        guard previous > 0 || change != 0 else { return nil }
        return Delta(text: "\(abs(change))", isUp: change >= 0, caption: "vs last week")
    }
}

/// A meal in a list: the photo, the dish, and what it counted as.
struct MealRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 13) {
            MealThumbnail(meal: meal)
            VStack(alignment: .leading, spacing: 3) {
                Text(MealDisplay.title(meal))
                    .font(WellieTheme.font(16, weight: .semibold))
                    .foregroundStyle(WellieTheme.ink)
                    .lineLimit(1)
                Text(MealDisplay.subtitle(meal))
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct HealthTile: View {
    let icon: String
    let label: String
    let value: String
    var delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WellieTheme.blue)
            Text(label)
                .font(WellieTheme.font(12, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
            Text(value)
                .font(WellieTheme.font(15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let delta {
                HStack(spacing: 2) {
                    Image(systemName: delta.isUp ? "arrow.up" : "arrow.down")
                        .font(.system(size: 9, weight: .bold))
                    Text(delta.text)
                        .font(WellieTheme.font(11, weight: .semibold))
                }
                .foregroundStyle(WellieTheme.muted)
                Text(delta.caption)
                    .font(WellieTheme.font(10, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(
            WellieTheme.surface.opacity(0.82),
            in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
        )
    }
}
