import Foundation

/// The 14-item Mediterranean Diet Adherence Screener used by the PREDIMED
/// trial. Each item is worth one point. This is the target metric for the app:
/// it is defined in terms of food-group frequency, which is exactly what a photo
/// can establish, and it is a validated instrument rather than something we made
/// up over a weekend.
public struct MedasItem: Sendable, Identifiable, Hashable {
    public let id: Int
    public let title: String
    public let rule: MedasRule
}

public enum MedasRule: Sendable, Hashable {
    /// Average servings per day across the window is at or above the threshold.
    case dailyAtLeast([FoodGroup], Double)
    /// Average servings per day across the window is strictly below the threshold.
    case dailyBelow([FoodGroup], Double)
    /// Servings across the window, rescaled to 7 days, at or above the threshold.
    case weeklyAtLeast([FoodGroup], Double)
    case weeklyBelow([FoodGroup], Double)
    /// Answered once in settings, not derivable from photographs.
    case habit(Habit)

    public enum Habit: String, Sendable, Hashable {
        case oliveOilIsMainFat
        case prefersWhiteMeat
    }
}

public enum Medas {
    /// Olive oil is scored in tablespoons by the original instrument; we hold
    /// one serving == 2 tbsp, so "4 tbsp/day" becomes "2 servings/day".
    public static let items: [MedasItem] = [
        .init(id: 1, title: "Olive oil is your main culinary fat", rule: .habit(.oliveOilIsMainFat)),
        .init(id: 2, title: "Olive oil ≥ 4 tbsp/day", rule: .dailyAtLeast([.oliveOil], 2.0)),
        .init(id: 3, title: "Vegetables ≥ 2 servings/day", rule: .dailyAtLeast([.vegetables], 2.0)),
        .init(id: 4, title: "Fruit ≥ 3 servings/day", rule: .dailyAtLeast([.fruit], 3.0)),
        .init(id: 5, title: "Red & processed meat < 1 serving/day", rule: .dailyBelow([.redMeat, .processedMeat], 1.0)),
        .init(id: 6, title: "Butter, margarine or cream < 1 serving/day", rule: .dailyBelow([.butter], 1.0)),
        .init(id: 7, title: "Sugary drinks < 1/day", rule: .dailyBelow([.sugaryDrinks], 1.0)),
        .init(id: 8, title: "Wine ≥ 7 glasses/week", rule: .weeklyAtLeast([.wine], 7.0)),
        .init(id: 9, title: "Legumes ≥ 3 servings/week", rule: .weeklyAtLeast([.legumes], 3.0)),
        .init(id: 10, title: "Fish or seafood ≥ 3 servings/week", rule: .weeklyAtLeast([.fish], 3.0)),
        .init(id: 11, title: "Sweets & pastry < 3 servings/week", rule: .weeklyBelow([.sweets, .pastry], 3.0)),
        .init(id: 12, title: "Nuts ≥ 3 servings/week", rule: .weeklyAtLeast([.nuts], 3.0)),
        .init(id: 13, title: "You prefer white meat to red meat", rule: .habit(.prefersWhiteMeat)),
        .init(id: 14, title: "Sofrito ≥ 2 servings/week", rule: .weeklyAtLeast([.sofrito], 2.0))
    ]
}

/// Which MEDAS items a food group feeds, and in which direction.
///
/// Two groups with the same footprint are interchangeable as far as the score is
/// concerned: nothing about your week changes if the model called brown rice
/// white. This is what separates an ambiguity worth a tap from one that is only
/// worth a mention.
public struct MedasFootprint: Sendable, Hashable {
    public struct Contribution: Sendable, Hashable {
        public let itemID: Int
        /// True for "less than" items, where servings count against you.
        public let isUpperBound: Bool
    }

    public let contributions: Set<Contribution>

    /// No scored item counts this group at all — `other`, and every grain.
    public var isUnscored: Bool { contributions.isEmpty }
}

extension Medas {
    public static func footprint(of group: FoodGroup, excludedItems: Set<Int> = []) -> MedasFootprint {
        var contributions: Set<MedasFootprint.Contribution> = []
        for item in items where !excludedItems.contains(item.id) {
            switch item.rule {
            case .dailyAtLeast(let groups, _), .weeklyAtLeast(let groups, _):
                if groups.contains(group) {
                    contributions.insert(.init(itemID: item.id, isUpperBound: false))
                }
            case .dailyBelow(let groups, _), .weeklyBelow(let groups, _):
                if groups.contains(group) {
                    contributions.insert(.init(itemID: item.id, isUpperBound: true))
                }
            case .habit:
                // Items 1 and 13 are answered once in settings and are not
                // derived from meals, so no photograph can move them.
                continue
            }
        }
        return MedasFootprint(contributions: contributions)
    }

    /// True when calling this food `a` instead of `b` changes what the week
    /// scores — the test for whether a recognition ambiguity deserves a
    /// confirmation. White meat against red meat passes it (red counts against
    /// item 5, white counts nowhere); whole against refined grains does not.
    public static func choiceChangesScore(
        _ a: FoodGroup,
        _ b: FoodGroup,
        excludedItems: Set<Int> = []
    ) -> Bool {
        guard a != b else { return false }
        return footprint(of: a, excludedItems: excludedItems)
            != footprint(of: b, excludedItems: excludedItems)
    }
}

public struct MedasConfiguration: Codable, Sendable, Hashable {
    /// Item ids removed from scoring; the denominator shrinks accordingly.
    ///
    /// Item 8 is excluded by default. PREDIMED awards a point for a glass of
    /// wine a day, and an app that nudges you toward drinking to raise a number
    /// is not the app we are building. Delete the `[8]` to score it.
    public var excludedItems: Set<Int>
    /// Length of the rolling window. Seven days, not one: daily perfection
    /// produces false failures — no fish on Tuesday is not a diet failure — and
    /// false failures are how habit-tracking apps get deleted in week three.
    public var windowDays: Int

    public init(excludedItems: Set<Int> = [8], windowDays: Int = 7) {
        self.excludedItems = excludedItems
        self.windowDays = windowDays
    }
}

public struct MedasResult: Sendable {
    public struct ItemResult: Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let passed: Bool
        /// Where you actually are, in the unit the item is stated in.
        public let observed: Double
        /// What the item asks for.
        public let target: Double
        public let isUpperBound: Bool
    }

    public let items: [ItemResult]
    public let score: Int
    public let maxScore: Int
    public let windowStart: EpochMillis
    public let windowEnd: EpochMillis
    /// Days in the window with at least one logged meal. A week with two logged
    /// meals will "pass" every upper-bound item for free, and the score is
    /// meaningless. Show this next to the score; do not hide it.
    public let daysLogged: Int
    public let windowDays: Int

    /// PREDIMED treats >= 10 of 14 as good adherence; rescaled if items are excluded.
    public var meetsGoodAdherence: Bool {
        guard maxScore > 0 else { return false }
        return Double(score) / Double(maxScore) >= 10.0 / 14.0
    }

    /// True when there is too little logging for the score to mean anything.
    public var isUnderreported: Bool { daysLogged * 2 < windowDays }
}

public struct MedasScorer: Sendable {
    public let configuration: MedasConfiguration

    public init(configuration: MedasConfiguration = .init()) {
        self.configuration = configuration
    }

    /// `windowEnd` is exclusive. Callers pass a day boundary in the user's local
    /// calendar converted to UTC millis — the scorer itself is timezone-free.
    public func score(
        meals: [MealEntry],
        habits: DietHabits,
        windowEnd: EpochMillis,
        calendar: Calendar = .current
    ) -> MedasResult {
        let days = max(1, configuration.windowDays)
        let windowStart = windowEnd - EpochMillis(days) * 86_400_000
        let inWindow = meals.filter { $0.eatenAt >= windowStart && $0.eatenAt < windowEnd }

        // Per meal, per group — not per item. `MealEntry.servings(of:)` is where
        // four fruit rows on one platter become one plate of fruit.
        var totals: [FoodGroup: Double] = [:]
        for meal in inWindow {
            for group in Set(meal.items.map(\.group)) {
                totals[group, default: 0] += meal.servings(of: group)
            }
        }

        var loggedDays = Set<Int>()
        for meal in inWindow {
            let day = calendar.startOfDay(for: Date(epochMillis: meal.eatenAt))
            loggedDays.insert(Int(day.timeIntervalSince1970 / 86_400))
        }

        let results = Medas.items
            .filter { !configuration.excludedItems.contains($0.id) }
            .map { item -> MedasResult.ItemResult in
                let (observed, target, passed, upper) = evaluate(item.rule, totals: totals, days: days, habits: habits)
                return .init(id: item.id, title: item.title, passed: passed,
                             observed: observed, target: target, isUpperBound: upper)
            }

        return MedasResult(
            items: results,
            score: results.count(where: \.passed),
            maxScore: results.count,
            windowStart: windowStart,
            windowEnd: windowEnd,
            daysLogged: loggedDays.count,
            windowDays: days
        )
    }

    private func evaluate(
        _ rule: MedasRule,
        totals: [FoodGroup: Double],
        days: Int,
        habits: DietHabits
    ) -> (observed: Double, target: Double, passed: Bool, isUpperBound: Bool) {
        func sum(_ groups: [FoodGroup]) -> Double {
            groups.reduce(0) { $0 + (totals[$1] ?? 0) }
        }
        let perDay = { (groups: [FoodGroup]) in sum(groups) / Double(days) }
        let perWeek = { (groups: [FoodGroup]) in sum(groups) * 7.0 / Double(days) }

        switch rule {
        case .dailyAtLeast(let g, let t): let v = perDay(g); return (v, t, v >= t, false)
        case .dailyBelow(let g, let t): let v = perDay(g); return (v, t, v < t, true)
        case .weeklyAtLeast(let g, let t): let v = perWeek(g); return (v, t, v >= t, false)
        case .weeklyBelow(let g, let t): let v = perWeek(g); return (v, t, v < t, true)
        case .habit(let h):
            let on = h == .oliveOilIsMainFat ? habits.oliveOilIsMainCulinaryFat : habits.prefersWhiteMeatOverRed
            return (on ? 1 : 0, 1, on, false)
        }
    }
}
