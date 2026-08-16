import Foundation

/// The in-memory read model. The log is the truth; this is a fold over it.
///
/// A personal tracker accumulates a few thousand events a year, so replaying
/// the whole log on launch costs milliseconds and buys a store with no
/// migration story to maintain.
public struct Projection: Sendable {
    public private(set) var meals: [UUID: MealEntry] = [:]
    public private(set) var messages: [UUID: LogMessage] = [:]

    public init() {}

    public init(replaying events: some Sequence<LoggedEvent>) {
        self.init()
        for event in events { apply(event) }
    }

    /// Fold one event in.
    ///
    /// `.unrecognized` falls through deliberately and is the reason this is a
    /// `switch` with an explicit case rather than a `default`: an event this
    /// build cannot read must contribute nothing to any total, any count, and
    /// any screen. It is carried in the log so it survives a round trip, and
    /// that is the whole of its job.
    public mutating func apply(_ event: LoggedEvent) {
        switch event.payload {
        case .mealLogged(let meal), .mealRevised(let meal):
            meals[meal.id] = meal
        case .mealDeleted(let id):
            meals.removeValue(forKey: id)

        case .messageSent(let message):
            messages[message.id] = message
        case .messageDeleted(let id):
            messages.removeValue(forKey: id)

        case .unrecognized:
            break
        }
    }
}

// MARK: - Reading a day

extension Projection {
    public func meals(on day: Date, calendar: Calendar = .current) -> [MealEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return meals.values
            .filter { interval.contains(Date(epochMillis: $0.eatenAt)) }
            .sorted { $0.eatenAt > $1.eatenAt }
    }

    /// What a day came to.
    public func nutrients(on day: Date, calendar: Calendar = .current) -> Nutrients {
        meals(on: day, calendar: calendar).reduce(Nutrients.zero) { $0 + $1.nutrients }
    }

    /// How many of the last `days` days have a meal written in them.
    ///
    /// Counts *days logged*, not a score: the app can see what it was told about
    /// and nothing else, and a number that dimmed because of what you ate would
    /// turn a record into a report card.
    ///
    /// Meals only, deliberately. Health knows about workouts and sleep on days
    /// you never opened the app, and counting those would make this a measure of
    /// whether you wore a watch rather than whether you kept a log.
    public func daysLogged(
        _ days: Int,
        endingAt end: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let starts = Set(meals.values.map { calendar.startOfDay(for: Date(epochMillis: $0.eatenAt)) })
        return (0..<days).count { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return false }
            return starts.contains(calendar.startOfDay(for: day))
        }
    }
}
