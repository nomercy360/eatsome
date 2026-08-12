import Foundation

/// One local day in history.
///
/// `servings` holds per-group quantities capped per meal and scaled by how much
/// of each plate was eaten.
public struct DayLog: Sendable, Hashable, Identifiable {
    /// Days since the Unix epoch in the local calendar. Stable and orderable,
    /// and safe as a `ForEach` id in a way a `Date` is not.
    public let id: Int
    public let start: Date
    public let mealCount: Int
    public let servings: [FoodKind: Double]

    public init(id: Int, start: Date, mealCount: Int, servings: [FoodKind: Double]) {
        self.id = id
        self.start = start
        self.mealCount = mealCount
        self.servings = servings
    }

    public var isLogged: Bool { mealCount > 0 }

    public func servings(of kind: FoodKind) -> Double { servings[kind] ?? 0 }

    /// How full the dot is drawn, 0…1.
    ///
    /// This measures logging, not eating well, and that split is deliberate:
    /// the dots say how much of the day the app actually saw. A dot that dimmed
    /// because of what you ate would turn a record into a report card.
    public var fill: Double {
        guard mealCount > 0 else { return 0 }
        return min(1, Double(mealCount) / 3.0)
    }
}

/// Per-day arithmetic for history screens.
public enum WeekRhythm {
    /// Oldest first, always exactly `days` entries: a day with nothing logged
    /// is a dot that has to be drawn, not a row that is missing.
    ///
    /// `windowEnd` is exclusive, so the last entry is today.
    public static func days(
        meals: [MealEntry],
        endingAt windowEnd: EpochMillis,
        days: Int,
        calendar: Calendar = .current
    ) -> [DayLog] {
        let count = max(1, days)
        // One step back from the exclusive end lands inside the final day.
        let lastDay = calendar.startOfDay(for: Date(epochMillis: windowEnd - 1))

        var byDay: [Int: (meals: Int, servings: [FoodKind: Double])] = [:]
        for meal in meals {
            let day = dayIndex(of: Date(epochMillis: meal.eatenAt), calendar: calendar)
            var bucket = byDay[day] ?? (0, [:])
            bucket.meals += 1
            for kind in Set(meal.items.map(\.kind)) {
                bucket.servings[kind, default: 0] += meal.servings(of: kind)
            }
            byDay[day] = bucket
        }

        return (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: lastDay) else { return nil }
            let index = dayIndex(of: start, calendar: calendar)
            let bucket = byDay[index] ?? (0, [:])
            return DayLog(id: index, start: start, mealCount: bucket.meals, servings: bucket.servings)
        }
    }

    /// Local day number used as the stable history key.
    private static func dayIndex(of date: Date, calendar: Calendar) -> Int {
        Int(calendar.startOfDay(for: date).timeIntervalSince1970 / 86_400)
    }
}
