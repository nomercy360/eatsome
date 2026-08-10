import Foundation

public struct DietConfiguration: Codable, Sendable, Hashable {
    /// Length of the rolling window. Seven days, not one: daily perfection
    /// produces false failures — no fish on Tuesday is not a diet failure — and
    /// false failures are how habit-tracking apps get deleted in week three.
    public var windowDays: Int

    public init(windowDays: Int = 7) {
        self.windowDays = windowDays
    }

    private enum CodingKeys: String, CodingKey { case windowDays, excludedItems }

    /// `excludedItems` was the app's only personalization: MEDAS item ids
    /// removed from scoring, with the denominator rescaling around them. It is
    /// gone rather than migrated, because editing your own diet is the general
    /// case of it and a per-instrument exclusion list has no meaning once the
    /// instrument is data. The key is still read and discarded so a config
    /// already cached on a phone keeps decoding.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windowDays = try c.decodeIfPresent(Int.self, forKey: .windowDays) ?? 7
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(windowDays, forKey: .windowDays)
    }
}

/// One-off answers that no photograph can settle, keyed by
/// `DietHabitQuestion.id`.
///
/// Two fixed booleans until the diet became data: MEDAS item 1 ("is olive oil
/// your main culinary fat") and item 13 ("do you prefer white meat to red"). A
/// low-sugar diet has no use for either, and a diet somebody builds may ask
/// something neither of them can express — so the answers are a bag keyed by
/// question id, and the questions live on the spec that asks them.
///
/// The two old fields still decode into the two MEDAS habit ids, which is the
/// whole of the migration: a `habits_updated` line written last year answers the
/// same two questions it always did.
public struct DietHabits: Codable, Sendable, Hashable {
    public private(set) var answers: [String: Bool]

    public init(answers: [String: Bool] = [:]) {
        self.answers = answers
    }

    /// The answer, or what the question says an unanswered person gets. Never
    /// nil: a habit with no answer would make the denominator depend on how far
    /// through onboarding somebody got.
    public func answer(_ question: DietHabitQuestion) -> Bool {
        answers[question.id] ?? question.defaultAnswer
    }

    public func answer(id: String, default fallback: Bool = true) -> Bool {
        answers[id] ?? fallback
    }

    public mutating func set(_ value: Bool, for id: String) {
        answers[id] = value
    }

    public func setting(_ value: Bool, for id: String) -> DietHabits {
        var copy = self
        copy.set(value, for: id)
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case answers
        case oliveOilIsMainCulinaryFat
        case prefersWhiteMeatOverRed
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var answers = try c.decodeIfPresent([String: Bool].self, forKey: .answers) ?? [:]
        if let legacy = try c.decodeIfPresent(Bool.self, forKey: .oliveOilIsMainCulinaryFat) {
            answers[DietPresets.oliveOilIsMainFatHabit] = legacy
        }
        if let legacy = try c.decodeIfPresent(Bool.self, forKey: .prefersWhiteMeatOverRed) {
            answers[DietPresets.prefersWhiteMeatHabit] = legacy
        }
        self.answers = answers
    }

    /// Writes the bag *and* the two legacy fields, so a build that predates this
    /// change reads a line written after it and still scores the two MEDAS
    /// habits. Costs two booleans per settings change; buys a downgrade that is
    /// not a silent two-point loss.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(answers, forKey: .answers)
        if let value = answers[DietPresets.oliveOilIsMainFatHabit] {
            try c.encode(value, forKey: .oliveOilIsMainCulinaryFat)
        }
        if let value = answers[DietPresets.prefersWhiteMeatHabit] {
            try c.encode(value, forKey: .prefersWhiteMeatOverRed)
        }
    }
}

// MARK: - Results

public struct DietResult: Sendable {
    public struct GoalResult: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let plainTitle: String?
        public let shape: DietGoal.Shape
        public let passed: Bool
        /// Where you actually are, in the unit the rule is stated in.
        public let observed: Double
        public let target: Double

        public var isUpperBound: Bool { shape.isUpperBound }

        public var isHabit: Bool {
            if case .habit = shape { return true }
            return false
        }
    }

    /// A constraint is reported, never scored.
    ///
    /// It has no `passed` that could be averaged with a goal's, because the one
    /// thing a vegetarian must be able to read is "there was chicken stock in
    /// the soup on Tuesday" — a fact an average is built to dissolve.
    public struct ConstraintResult: Sendable, Identifiable {
        public let id: String
        public let title: String
        public let shape: DietConstraint.Shape
        public let breaks: [Break]

        public var isKept: Bool { breaks.isEmpty }
    }

    /// One meal that broke a constraint, named well enough to be recognised.
    public struct Break: Sendable, Hashable, Identifiable {
        public let mealID: UUID
        public let at: EpochMillis
        /// The dish it was in, when recognition named one — "the soup", not
        /// "white_meat". Nil on a meal from before dishes existed.
        public let dish: String?
        /// The food that did it, for a `never`. Nil for an eating-window break,
        /// where the food is not what was wrong.
        public let group: FoodGroup?

        public var id: UUID { mealID }
    }

    public let spec: DietSpec
    public let goals: [GoalResult]
    public let constraints: [ConstraintResult]
    public let score: Int
    public let maxScore: Int
    public let windowStart: EpochMillis
    public let windowEnd: EpochMillis
    /// Days in the window with at least one logged meal. A week with two logged
    /// meals will "pass" every upper-bound rule for free, and the score is
    /// meaningless. Show this next to the score; do not hide it.
    public let daysLogged: Int
    public let windowDays: Int

    /// Goals met out of goals set, on the app's own scale.
    ///
    /// The one figure every diet shares. A plant-forward week and a MEDAS week
    /// have different rules, different counts and nothing in common except this,
    /// which is what makes the day glance readable after somebody switches.
    /// Fractional so a day can be averaged without rounding twice; `OliveRating`
    /// draws `Int(rounded())`.
    public var olives: Double {
        guard maxScore > 0 else { return 0 }
        return Double(score) / Double(maxScore) * 5
    }

    /// PREDIMED treats ≥ 10 of 14 as good adherence. Only meaningful for a spec
    /// that *is* the instrument, which is why it asks.
    public var meetsGoodAdherence: Bool? {
        guard spec.instrument != nil, maxScore > 0 else { return nil }
        return Double(score) / Double(maxScore) >= 10.0 / 14.0
    }

    /// True when there is too little logging for the score to mean anything.
    public var isUnderreported: Bool { daysLogged * 2 < windowDays }

    public var brokenConstraints: [ConstraintResult] { constraints.filter { !$0.isKept } }
}

// MARK: - The window

/// Everything a rule shape might need to read, computed once.
///
/// The old scorer collapsed a week to `[FoodGroup: Double]` before evaluating
/// anything, which is why it could express "vegetables twice a day" and could
/// not express "a protein source at every meal" or "nothing after eight". Those
/// are not exotic rules — they are what most diets that talk about meals rather
/// than days are made of. The totals are still here and still the fast path;
/// what changed is that the meals did not get thrown away first.
public struct ScoringWindow: Sendable {
    public let meals: [MealEntry]
    public let start: EpochMillis
    public let end: EpochMillis
    public let days: Int
    public let calendar: Calendar
    public let servingGrams: [String: Double]
    public let proteinPerServing: [String: Double]
    public let foods: FoodNutrientTable?

    /// Servings per group across the window, capped per meal and scaled by
    /// share — `MealEntry.servings(of:)` is where four fruit rows on one platter
    /// become one plate of fruit.
    public let totals: [FoodGroup: Double]
    /// Local day number → the meals eaten on it.
    public let byDay: [Int: [MealEntry]]

    public init(
        meals: [MealEntry],
        start: EpochMillis,
        end: EpochMillis,
        days: Int,
        calendar: Calendar = .current,
        servingGrams: [String: Double] = ServingWeight.defaultGrams,
        proteinPerServing: [String: Double] = Protein.defaultGramsPerServing,
        foods: FoodNutrientTable? = nil
    ) {
        let inWindow = meals.filter { $0.eatenAt >= start && $0.eatenAt < end }
        self.meals = inWindow
        self.start = start
        self.end = end
        self.days = max(1, days)
        self.calendar = calendar
        self.servingGrams = servingGrams
        self.proteinPerServing = proteinPerServing
        self.foods = foods

        var totals: [FoodGroup: Double] = [:]
        var byDay: [Int: [MealEntry]] = [:]
        for meal in inWindow {
            for group in Set(meal.items.map(\.group)) {
                totals[group, default: 0] += meal.servings(of: group, servingGrams: servingGrams)
            }
            byDay[Self.dayNumber(of: meal.eatenAt, calendar: calendar), default: []].append(meal)
        }
        self.totals = totals
        self.byDay = byDay
    }

    public var daysLogged: Int { byDay.count }

    static func dayNumber(of time: EpochMillis, calendar: Calendar) -> Int {
        let day = calendar.startOfDay(for: Date(epochMillis: time))
        return Int(day.timeIntervalSince1970 / 86_400)
    }

    func servings(of groups: [FoodGroup]) -> Double {
        groups.reduce(0) { $0 + (totals[$1] ?? 0) }
    }

    /// The wall-clock hour a meal was eaten at, in the user's own calendar.
    ///
    /// The scorer is otherwise timezone-free and this is the one rule that
    /// cannot be: an eating window is stated in local hours because that is the
    /// only way a person can state it. It reads the same `Calendar` the day
    /// buckets already use, so a window and the day it sits in can never
    /// disagree about which timezone they are in.
    func localHour(of time: EpochMillis) -> Double {
        let date = Date(epochMillis: time)
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
    }
}

public enum DietScoring {
    /// Below this, a logged thing is not a meal for the purpose of a per-meal
    /// rule.
    ///
    /// `eachMeal` needs an answer to "was that a meal?", and the log does not
    /// carry one — a black coffee at 8am is a `MealEntry` exactly like dinner
    /// is. Without a floor, "a protein source at every meal" fails every day
    /// somebody logs a coffee, which is every day, and a rule that can never
    /// pass is worse than no rule. Three-quarters of a serving is roughly a
    /// plate rather than a cup, and it is the one judgement in this shape:
    /// stated here so it can be argued with rather than buried in a filter.
    public static let mealFloorServings = 0.75
}

// MARK: - The scorer

public struct DietScorer: Sendable {
    public let spec: DietSpec
    public let configuration: DietConfiguration

    public init(spec: DietSpec, configuration: DietConfiguration = .init()) {
        self.spec = spec
        self.configuration = configuration
    }

    /// `windowEnd` is exclusive. Callers pass a day boundary in the user's local
    /// calendar converted to UTC millis.
    public func score(
        meals: [MealEntry],
        habits: DietHabits,
        windowEnd: EpochMillis,
        calendar: Calendar = .current,
        servingGrams: [String: Double] = ServingWeight.defaultGrams,
        proteinPerServing: [String: Double] = Protein.defaultGramsPerServing,
        foods: FoodNutrientTable? = nil
    ) -> DietResult {
        let days = max(1, configuration.windowDays)
        let windowStart = windowEnd - EpochMillis(days) * 86_400_000
        let window = ScoringWindow(
            meals: meals,
            start: windowStart,
            end: windowEnd,
            days: days,
            calendar: calendar,
            servingGrams: servingGrams,
            proteinPerServing: proteinPerServing,
            foods: foods
        )

        let goals = spec.goals.map { goal -> DietResult.GoalResult in
            let (observed, passed) = evaluate(goal.shape, in: window, habits: habits)
            return .init(
                id: goal.id,
                title: goal.title,
                plainTitle: goal.plainTitle,
                shape: goal.shape,
                passed: passed,
                observed: observed,
                target: goal.shape.target
            )
        }

        let constraints = spec.constraints
            .filter(\.isEnabled)
            .map { constraint in
                DietResult.ConstraintResult(
                    id: constraint.id,
                    title: constraint.title,
                    shape: constraint.shape,
                    breaks: breaks(of: constraint.shape, in: window)
                )
            }

        return DietResult(
            spec: spec,
            goals: goals,
            constraints: constraints,
            score: goals.count(where: \.passed),
            maxScore: goals.count,
            windowStart: windowStart,
            windowEnd: windowEnd,
            daysLogged: window.daysLogged,
            windowDays: days
        )
    }

    private func evaluate(
        _ shape: DietGoal.Shape,
        in window: ScoringWindow,
        habits: DietHabits
    ) -> (observed: Double, passed: Bool) {
        let days = Double(window.days)

        switch shape {
        case .dailyAtLeast(let groups, let target):
            let value = window.servings(of: groups) / days
            return (value, value >= target)

        case .dailyBelow(let groups, let target):
            let value = window.servings(of: groups) / days
            return (value, value < target)

        case .weeklyAtLeast(let groups, let target):
            let value = window.servings(of: groups) * 7 / days
            return (value, value >= target)

        case .weeklyBelow(let groups, let target):
            let value = window.servings(of: groups) * 7 / days
            return (value, value < target)

        case .habit(let id):
            let question = spec.habits.first { $0.id == id }
            let on = question.map(habits.answer) ?? habits.answer(id: id)
            return (on ? 1 : 0, on)

        case .eachMeal(let groups):
            let counted = window.meals.filter {
                $0.totalServings(servingGrams: window.servingGrams) >= DietScoring.mealFloorServings
            }
            guard !counted.isEmpty else { return (0, false) }
            let wanted = Set(groups)
            let met = counted.count { !Set($0.items.map(\.group)).isDisjoint(with: wanted) }
            let fraction = Double(met) / Double(counted.count)
            return (fraction, met == counted.count)

        case .dailyAtLeastGrams(let nutrient, let target):
            let total = Nutrition.total(
                in: window.meals,
                gramsPerServing: window.proteinPerServing,
                foods: window.foods
            ).nutrients
            let value: Double = switch nutrient {
            case .protein: total.protein
            }
            // Averaged over the window's days rather than over the days that
            // were logged: a target met on the two days somebody remembered to
            // log is not a target met, and dividing by `daysLogged` would say
            // it was.
            let perDay = value / days
            return (perDay, perDay >= target)
        }
    }

    private func breaks(
        of shape: DietConstraint.Shape,
        in window: ScoringWindow
    ) -> [DietResult.Break] {
        switch shape {
        case .never(let groups):
            let banned = Set(groups)
            return window.meals.flatMap { meal -> [DietResult.Break] in
                // One break per meal, not per row: a bolognese recognised as
                // three meat rows is one broken promise, and three lines under
                // the olives would read as three dinners.
                guard let item = meal.items.first(where: { banned.contains($0.group) }) else { return [] }
                return [.init(mealID: meal.id, at: meal.eatenAt, dish: item.dish, group: item.group)]
            }
            .sorted { $0.at < $1.at }

        case .eatingWindow(let startHour, let endHour):
            return window.meals.compactMap { meal in
                let hour = window.localHour(of: meal.eatenAt)
                let inside = startHour <= endHour
                    ? (hour >= startHour && hour < endHour)
                    // A window that runs past midnight — 20:00 to 04:00 — is two
                    // intervals on the clock and one to a person.
                    : (hour >= startHour || hour < endHour)
                guard !inside else { return nil }
                return DietResult.Break(
                    mealID: meal.id,
                    at: meal.eatenAt,
                    dish: meal.items.first?.dish,
                    group: nil
                )
            }
            .sorted { $0.at < $1.at }
        }
    }
}

// MARK: - Streaks

public enum DietStreak {
    /// Consecutive days back from `endingAt` with no break of this constraint.
    ///
    /// Deliberately outside the scorer and outside the window: "kept 34 days" is
    /// the number a vegetarian actually wants, and it is a fact about the whole
    /// log rather than about the rolling seven. A day with nothing logged does
    /// not break a streak and does not extend it — no evidence is not evidence
    /// of a lapse, and it is not evidence of keeping either. The count stops at
    /// the first day that was logged and broke it.
    public static func daysKept(
        _ constraint: DietConstraint,
        meals: [MealEntry],
        endingAt end: EpochMillis,
        calendar: Calendar = .current,
        limit: Int = 400
    ) -> Int {
        guard case .never(let groups) = constraint.shape else { return 0 }
        let banned = Set(groups)

        var brokenDays = Set<Int>()
        for meal in meals where meal.eatenAt < end {
            guard meal.items.contains(where: { banned.contains($0.group) }) else { continue }
            brokenDays.insert(ScoringWindow.dayNumber(of: meal.eatenAt, calendar: calendar))
        }
        guard !brokenDays.isEmpty else {
            let earliest = meals.map(\.eatenAt).min() ?? end
            let today = ScoringWindow.dayNumber(of: end - 1, calendar: calendar)
            return min(limit, max(0, today - ScoringWindow.dayNumber(of: earliest, calendar: calendar) + 1))
        }

        let today = ScoringWindow.dayNumber(of: end - 1, calendar: calendar)
        var kept = 0
        var day = today
        while kept < limit, !brokenDays.contains(day) {
            kept += 1
            day -= 1
        }
        return kept
    }
}
