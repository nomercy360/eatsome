import Foundation

/// One local day, and how much of it the app saw.
///
/// What survived `WeekRhythm`, which counted servings per food kind and went
/// with the taxonomy. A day is now what was logged and what it came to — no
/// per-food buckets, because there is no vocabulary left to bucket by.
public struct DayLog: Sendable, Hashable, Identifiable {
    /// Days since the Unix epoch in the local calendar. Stable and orderable,
    /// and safe as a `ForEach` id in a way a `Date` is not.
    public let id: Int
    public let start: Date
    public let mealCount: Int
    public let nutrients: Nutrients

    public init(id: Int, start: Date, mealCount: Int, nutrients: Nutrients = .zero) {
        self.id = id
        self.start = start
        self.mealCount = mealCount
        self.nutrients = nutrients
    }

    public var isLogged: Bool { mealCount > 0 }

    /// How full the dot is drawn, 0…1.
    ///
    /// This measures logging, not eating well, and that split is deliberate:
    /// the dots say how much of the day the app actually saw. A dot that dimmed
    /// because of what you ate would turn a record into a report card.
    public var fill: Double {
        guard mealCount > 0 else { return 0 }
        return min(1, Double(mealCount) / 3.0)
    }

    /// Consecutive local days ending at `endingAt`, oldest first, gaps included.
    ///
    /// A day with nothing on it is a dot that has to be drawn empty, not a day
    /// the list quietly leaves out.
    public static func days(
        meals: [MealEntry],
        endingAt end: EpochMillis,
        days count: Int,
        calendar: Calendar = .current
    ) -> [DayLog] {
        let lastStart = calendar.startOfDay(for: Date(epochMillis: end).addingTimeInterval(-1))
        var byDay: [Date: [MealEntry]] = [:]
        for meal in meals {
            byDay[calendar.startOfDay(for: Date(epochMillis: meal.eatenAt)), default: []].append(meal)
        }
        return (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: lastStart) else {
                return nil
            }
            let onDay = byDay[start] ?? []
            return DayLog(
                id: Int(start.timeIntervalSince1970 / 86_400),
                start: start,
                mealCount: onDay.count,
                nutrients: onDay.reduce(Nutrients.zero) { $0 + $1.nutrients }
            )
        }
    }
}
