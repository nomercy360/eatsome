import ShamanCore
import SwiftUI

/// Screen `7f`. The old Today screen's job, one tap deep.
///
/// "How much have I eaten today" lives in the pinned strip as a glance, and
/// expands into this: the day's olives, what today counted for, and the meals —
/// each row opening `2e`. The thread stays visible behind it; swiping down goes
/// back to logging.
///
/// It doubles as the view for an earlier day, reached from a dot on `My week`.
/// The two were separate screens when Today was a tab, and they were the same
/// screen with one of them missing an "add" button.
struct DaySheet: View {
    let day: Date

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var openMeal: MealEntry?
    @State private var addingByHand = false
    @State private var draft = ""

    private var meals: [MealEntry] { model.meals(on: day) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: WellieTheme.cardSpacing) {
                    if meals.isEmpty {
                        emptyDay
                    } else {
                        olivesCard
                        countedCard
                        mealsCard
                    }
                    if isToday { healthCard }
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle(DayFormat.title(day))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text(day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                        .font(WellieTheme.font(13, weight: .semibold))
                        .foregroundStyle(WellieTheme.muted)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
            .navigationDestination(item: $openMeal) { MealDetailView(meal: $0) }
            .sheet(isPresented: $addingByHand) {
                FixScreen(purpose: .add, text: $draft) {
                    Task {
                        await model.send(said: draft, on: day)
                        draft = ""
                    }
                }
            }
        }
        .wellieScreen()
    }

    // MARK: - The day's olives

    /// The headline, and the one line that stops it reading as a verdict:
    /// a day is not finished until it is finished.
    private var olivesCard: some View {
        let rating = model.olives(on: day)
        return VStack(alignment: .leading, spacing: 14) {
            Text(headline(rating))
                .font(WellieTheme.font(26, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let rating {
                // The headline of this screen, so it carries the size. Elsewhere
                // the olives annotate a meal and stay small.
                OliveRow(olives: rating.olives, size: 36)
                WellieProse(
                    isToday
                        ? "Portion-weighted across the day — it settles as the day does."
                        : "Portion-weighted across the day."
                )
            }
        }
        .wellieCard(color: WellieTheme.ice, padding: 24)
    }

    private func headline(_ rating: OliveRating?) -> String {
        guard let rating else { return "Nothing logged yet." }
        return isToday ? "\(rating.spelled) so far" : rating.spelled
    }

    // MARK: - Counted today

    private var countedCard: some View {
        let total = model.nutrients(in: meals)
        return VStack(alignment: .leading, spacing: 15) {
            WellieSectionTitle(text: isToday ? "Counted today" : "Counted")

            FlowLayout(spacing: 7, lineSpacing: 7) {
                ForEach(counted, id: \.group) { entry in
                    WellieChip(text: entry.label)
                }
                // Protein sits in the same row as the food it came from, as one
                // more thing the day counted for. It is the only figure here
                // because it is the only one of the five that is a floor — the
                // rest are ranges, and four more numbers in a chip row would say
                // they were all targets to hit.
                WellieChip(text: "Protein \(Int(total.nutrients.protein.rounded())) g", style: .outline)
            }

            if !total.isComplete {
                // A partial total that does not say it is partial is the exact
                // failure this whole design is arranged against.
                Text("\(Int(total.unresolvedGrams.rounded())) g not recognised — "
                     + "this is short by whatever it was.")
                    .font(WellieTheme.font(12, weight: .medium))
                    .foregroundStyle(WellieTheme.attention)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .wellieCard()
    }

    /// Each group with the number of times it appeared, in the order it was
    /// first eaten. "Sweets ½" in the mock is a half serving, so the count is
    /// servings rather than rows.
    private var counted: [(group: FoodGroup, label: String)] {
        var order: [FoodGroup] = []
        var servings: [FoodGroup: Double] = [:]
        for meal in meals.sorted(by: { $0.eatenAt < $1.eatenAt }) {
            for group in meal.items.map(\.group) where servings[group] == nil {
                order.append(group)
                servings[group] = 0
            }
        }
        for group in order {
            servings[group] = meals.reduce(0) { $0 + $1.servings(of: group) }
        }

        return order.compactMap { group in
            guard let amount = servings[group], amount > 0 else { return nil }
            return (group, "\(group.shortName)\(Self.quantity(amount))")
        }
    }

    /// Nothing for one serving, "×3" for three, "½" for a half. A bare name is
    /// the common case and a suffix on every chip would be noise.
    private static func quantity(_ servings: Double) -> String {
        if servings < 0.75 { return " ½" }
        let rounded = Int(servings.rounded())
        return rounded > 1 ? " ×\(rounded)" : ""
    }

    // MARK: - The meals

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(meals.sorted { $0.eatenAt < $1.eatenAt }) { meal in
                Button { openMeal = meal } label: {
                    HStack(spacing: 13) {
                        MealThumbnail(meal: meal, side: 44, radius: 14)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(MealDisplay.title(meal))
                                .font(WellieTheme.font(16, weight: .semibold))
                                .foregroundStyle(WellieTheme.ink)
                                .lineLimit(1)
                            Text(MealDisplay.whenAndWhat(meal))
                                .font(WellieTheme.font(13, weight: .medium))
                                .foregroundStyle(WellieTheme.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        OliveRow(olives: model.olives(for: meal).olives, size: 15)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(WellieTheme.faint)
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .wellieListCard()
    }

    // MARK: - Empty

    /// A gap is information, and on an earlier day it is the one thing still
    /// fixable. Today's blank says less, because the composer is right behind
    /// this sheet.
    private var emptyDay: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(text: "Nothing logged")
            WellieProse(
                isToday
                    ? "Tell the thread what you ate and it appears here."
                    : "A gap is information too. If you remember what you ate, it still counts."
            )
            if isToday {
                Button("Back to the thread") { dismiss() }
                    .buttonStyle(WellieSecondaryButtonStyle())
            } else {
                Button("Add a meal for this day") { addingByHand = true }
                    .buttonStyle(WellieSecondaryButtonStyle())
            }
        }
        .wellieCard()
    }

    // MARK: - Health

    /// Sleep, workouts and weight are properties of a day, so they live on the
    /// day. They were on the old Today screen and `7f` does not draw them —
    /// dropping them silently would have been the wrong way to read a mock that
    /// is about the olives.
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
                            Delta(
                                text: DayFormat.duration(abs($0)),
                                isUp: $0 >= 0,
                                caption: "vs your average"
                            )
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
                    // iOS makes a refused read look exactly like an empty store,
                    // so the app must not claim it knows which one this is.
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

/// Sleep, workouts or weight — a value, and how it compares.
///
/// Deliberately not coloured green or red: down is not always good on weight and
/// up is not always an achievement on sleep. The arrow says which way, the
/// number says how far, and the judgement stays with the person.
struct HealthTile: View {
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
