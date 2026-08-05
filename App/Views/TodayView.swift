import ShamanCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCapture = false

    private var meals: [MealEntry] { model.mealsToday() }
    private var foodGroups: [FoodGroup] {
        var seen = Set<FoodGroup>()
        return meals.flatMap(\.items).map(\.group).filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    adherenceHero
                    todayCard
                    mealsCard
                    healthCard

                    if let error = model.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(WellieTheme.danger)
                            .wellieCard(color: WellieTheme.card)
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.bottom, 24)
            }
            .background(WellieTheme.background)
            .navigationTitle("EATSOME")
            .navigationBarTitleDisplayMode(.inline)
            // Health is fetched when the app becomes active; a pull covers the
            // rest. A toolbar button only advertises that the sync is manual.
            .refreshable { await model.refreshHealth() }
            .safeAreaInset(edge: .bottom) {
                Button { showingCapture = true } label: {
                    Label("Add meal", systemImage: "camera.fill")
                }
                .buttonStyle(WelliePrimaryButtonStyle())
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 8)
                .padding(.bottom, 6)
                .background(.bar)
            }
            .sheet(isPresented: $showingCapture) { MealCaptureView() }
        }
        .wellieScreen()
    }

    /// While there is too little logged to mean anything, the days counter leads
    /// and the score is a footnote. Printing a huge number and then explaining
    /// underneath that it cannot be trusted is the wrong way round.
    private var adherenceHero: some View {
        let result = model.adherence()
        return NavigationLink {
            AdherenceView()
        } label: {
            VStack(spacing: 10) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(WellieTheme.font(14, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)

                if result.isUnderreported {
                    WellieKicker(text: "Days logged")
                    figure("\(result.daysLogged)", of: "/ \(result.windowDays)")
                    Text("A few consistent days will reveal your Mediterranean pattern.")
                        .font(WellieTheme.font(15, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                    Text("Adherence so far: \(result.score) of \(result.maxScore)")
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                } else {
                    WellieKicker(text: "Rolling adherence")
                    figure("\(result.score)", of: "/ \(result.maxScore)")
                    Text(heroMessage(result))
                        .font(WellieTheme.font(15, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 330)
                    Text("From \(result.daysLogged) of \(result.windowDays) days")
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .wellieCard(color: WellieTheme.ice, padding: 22)
        }
        .buttonStyle(.plain)
    }

    private func figure(_ value: String, of total: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(WellieTheme.font(60, weight: .bold))
            Text(total)
                .font(WellieTheme.font(26, weight: .bold))
                .foregroundStyle(WellieTheme.muted)
        }
    }

    /// What you have eaten today and, more usefully, what you have not. A lone
    /// chip says what you collected; this says what is left, which is the only
    /// reason to open the screen before a meal.
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            WellieKicker(text: "Today")

            if foodGroups.isEmpty {
                Text("Nothing logged yet.")
                    .font(WellieTheme.font(15, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            } else {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(foodGroups, id: \.self) { group in
                        Label(group.displayName, systemImage: "checkmark")
                            .font(WellieTheme.font(12, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundStyle(WellieTheme.blue)
                            .background(WellieTheme.softBlue, in: Capsule())
                    }
                }
            }

            if !dailyShortfalls.isEmpty {
                shortfallLine(title: "Still today", entries: dailyShortfalls)
            }
            if !weeklyShortfalls.isEmpty {
                shortfallLine(title: "This week", entries: weeklyShortfalls)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .wellieCard(color: WellieTheme.card)
    }

    private func shortfallLine(title: String, entries: [Shortfall]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(WellieTheme.font(12, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
            Text(entries.map(\.description).joined(separator: " · "))
                .font(WellieTheme.font(14, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private struct Shortfall: Identifiable {
        let id: Int
        let name: String
        let observed: Double
        let target: Double

        var description: String {
            let have = observed.formatted(.number.precision(.fractionLength(observed == observed.rounded() ? 0 : 1)))
            return "\(name) \(have)/\(target.formatted(.number.precision(.fractionLength(0))))"
        }
    }

    /// Daily lower-bound items measured against today alone, not the rolling
    /// average — "still today" has to mean today.
    private var dailyShortfalls: [Shortfall] {
        let excluded = model.config.medas.excludedItems
        return Medas.items.compactMap { item in
            guard !excluded.contains(item.id), case .dailyAtLeast(let groups, let target) = item.rule else { return nil }
            let observed = groups.reduce(0.0) { total, group in
                total + meals.reduce(0) { $0 + $1.servings(of: group) }
            }
            guard observed < target else { return nil }
            return Shortfall(id: item.id, name: groups.map(\.displayName).joined(separator: " / "),
                             observed: observed, target: target)
        }
    }

    /// Weekly ones come from the scorer, which already rescales to seven days.
    private var weeklyShortfalls: [Shortfall] {
        let weekly = Set(Medas.items.compactMap { item -> Int? in
            if case .weeklyAtLeast = item.rule { return item.id }
            return nil
        })
        return model.adherence().items
            .filter { weekly.contains($0.id) && !$0.passed }
            .map { Shortfall(id: $0.id, name: $0.title.components(separatedBy: " ≥").first ?? $0.title,
                             observed: $0.observed, target: $0.target) }
    }

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WellieKicker(text: "Today's meals")
                Spacer()
                Text("\(meals.count)")
                    .font(WellieTheme.font(13, weight: .bold))
                    .foregroundStyle(WellieTheme.blue)
            }
            .padding(.bottom, 8)

            if meals.isEmpty {
                Text("No meals logged yet. A photo is enough to begin.")
                    .font(WellieTheme.font(15, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    NavigationLink {
                        MealDetailView(meal: meal)
                    } label: {
                        MealHistoryRow(meal: meal)
                    }
                    .buttonStyle(.plain)

                    if index < meals.count - 1 { Divider() }
                }
            }
        }
        .wellieCard(color: WellieTheme.card)
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                WellieKicker(text: "From Apple Health")
                Spacer()
                if model.isLoadingHealth { ProgressView().controlSize(.small) }
            }

            if !model.hasRequestedHealthAccess
                && model.healthSnapshot.workouts.isEmpty
                && model.healthSnapshot.sleep.isEmpty
                && model.healthSnapshot.weights.isEmpty {
                Button("Connect Apple Health") { Task { await model.connectHealth() } }
                    .buttonStyle(WellieSecondaryButtonStyle())
            } else {
                HStack(alignment: .top, spacing: 10) {
                    HealthMetric(
                        icon: "moon.fill",
                        label: "Sleep",
                        value: model.latestSleep.map { duration($0.asleep) } ?? "None",
                        delta: model.sleepDeltaAgainstAverage.map {
                            Delta(text: duration(abs($0)), isUp: $0 >= 0, caption: "vs your average")
                        }
                    )
                    HealthMetric(
                        icon: "figure.run",
                        label: "Workouts",
                        value: "\(model.workoutCount(weeksAgo: 0))",
                        delta: workoutDelta
                    )
                    HealthMetric(
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
                    Text("No samples. Either nothing is recorded, or Health access was declined — iOS does not tell apps which.")
                        .font(WellieTheme.font(12, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                }
            }

            if let error = model.healthError {
                Text(error)
                    .font(WellieTheme.font(12, weight: .medium))
                    .foregroundStyle(WellieTheme.warningText)
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

    private func heroMessage(_ result: MedasResult) -> String {
        if result.isUnderreported {
            return "A few consistent days will reveal your Mediterranean pattern."
        }
        return result.meetsGoodAdherence
            ? "Your seven-day pattern is on track. Keep the rhythm gentle and steady."
            : "Your week is taking shape. The detail view shows the easiest next step."
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

private struct MealHistoryRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            if let photo = PhotoStore.shared.image(for: meal.photoHash) {
                Image(uiImage: photo)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Image(systemName: meal.source == .photo ? "camera.fill" : "fork.knife")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(WellieTheme.blue)
                    .frame(width: 44, height: 44)
                    .background(WellieTheme.softBlue, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(MealDisplay.title(meal))
                    .font(WellieTheme.font(16, weight: .semibold))
                    .lineLimit(1)
                Text(MealDisplay.subtitle(meal))
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(Date(epochMillis: meal.eatenAt).formatted(date: .omitted, time: .shortened))
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
        .padding(.vertical, 10)
    }
}

/// A change with a direction and no opinion about it.
///
/// Deliberately not coloured green or red: down is not always good on weight and
/// up is not always an achievement on sleep. The arrow says which way, the
/// number says how far, and the judgement stays with the person.
struct Delta {
    let text: String
    let isUp: Bool
    let caption: String
}

private struct HealthMetric: View {
    let icon: String
    let label: String
    let value: String
    var delta: Delta?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
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
        .padding(12)
        .background(WellieTheme.elevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

enum MealDisplay {
    /// One name plus a count, rather than three labels glued together and then
    /// cut off mid-word. "cherries +3" survives any row width.
    static func title(_ meal: MealEntry) -> String {
        let labels = meal.items.compactMap(\.label).filter { !$0.isEmpty }
        let groups = uniqueGroups(meal)
        let lead = labels.first ?? groups.first?.displayName ?? "Meal"
        let rest = meal.items.count - 1
        return rest > 0 ? "\(lead) +\(rest)" : lead
    }

    static func subtitle(_ meal: MealEntry) -> String {
        let groups = uniqueGroups(meal).prefix(4).map(\.displayName).joined(separator: " · ")
        // A half-counted meal looks identical to a whole one in the list
        // otherwise, and the difference is the whole point of the switch.
        return meal.eaten == .part ? "\(groups) · ate part" : groups
    }

    private static func uniqueGroups(_ meal: MealEntry) -> [FoodGroup] {
        var seen = Set<FoodGroup>()
        return meal.items.map(\.group).filter { seen.insert($0).inserted }
    }
}

enum WeightFormat {
    static var usesMetric: Bool { Locale.current.measurementSystem == .metric }
    static var unit: String { usesMetric ? "kg" : "lb" }

    static func value(_ kilograms: Double) -> Double {
        usesMetric ? kilograms : kilograms * 2.204_622_621_8
    }

    static func string(_ kilograms: Double) -> String {
        "\(value(kilograms).formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}
