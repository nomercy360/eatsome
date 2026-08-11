import Foundation

/// The dishes you actually repeat, ranked for the chips above the keyboard.
///
/// Built from the log rather than from a saved list, which is the point: nobody
/// curates a library of their own dinners, but everybody re-eats them. A dish
/// earns a chip by being logged, and stops having one by not being logged — no
/// screen to maintain, and deleting a meal takes its evidence with it.
///
/// Ranking is frequency × recency × daypart, and all three are needed. Frequency
/// alone offers you the thing you eat most at 3 am. Recency alone offers you
/// yesterday's one-off. Daypart alone offers nothing at all until there is a lot
/// of history. Together they answer the question the chips are actually for,
/// which is "what am I most likely about to type".
public enum DishLibrary {
    public struct Entry: Sendable, Hashable, Identifiable {
        public var id: String { name }
        public let name: String
        /// How many meals contained it. Shown on the chip as "×6" — small, and
        /// the reason to trust the suggestion.
        public let timesLogged: Int
        public let lastLoggedAt: EpochMillis
        /// The dish exactly as it was last logged, ingredients and weights and
        /// all. This is what "it logs with that dish's usual portion and
        /// ingredients" means: tapping a chip and sending it unchanged does not
        /// need to buy a model call to find out what lentil soup is again.
        public let lastLogged: MealDish

        public init(name: String, timesLogged: Int, lastLoggedAt: EpochMillis, lastLogged: MealDish) {
            self.name = name
            self.timesLogged = timesLogged
            self.lastLoggedAt = lastLoggedAt
            self.lastLogged = lastLogged
        }
    }

    /// How long it takes for a dish's recency to count for half as much.
    ///
    /// Two weeks: long enough that a weekly dish never falls off the list,
    /// short enough that the soup you stopped making in March stops being
    /// offered in August.
    public static let recencyHalfLifeDays = 14.0

    /// How much of a dish's rank survives being suggested in the wrong part of
    /// the day. Not zero — people do eat soup for breakfast — but enough that
    /// three lunches outrank one breakfast at lunchtime.
    private static let wrongDaypartFloor = 0.35

    /// Every dish the log has ever seen, newest-first within equal use.
    public static func entries(in meals: some Sequence<MealEntry>) -> [Entry] {
        var counts: [String: Int] = [:]
        var latest: [String: (at: EpochMillis, dish: MealDish)] = [:]

        for meal in meals {
            for dish in meal.storedDishes ?? [] {
                let name = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
                // Corrections land in an unnamed dish (see `MealDish.regrouped`),
                // and "" is not something anyone would tap.
                guard !name.isEmpty else { continue }
                counts[name, default: 0] += 1
                if (latest[name]?.at ?? 0) <= meal.eatenAt {
                    latest[name] = (meal.eatenAt, dish)
                }
            }
        }

        return counts.compactMap { name, count in
            guard let last = latest[name] else { return nil }
            return Entry(
                name: name,
                timesLogged: count,
                lastLoggedAt: last.at,
                lastLogged: last.dish
            )
        }
        .sorted {
            $0.timesLogged == $1.timesLogged
                ? $0.lastLoggedAt > $1.lastLoggedAt
                : $0.timesLogged > $1.timesLogged
        }
    }

    /// The chips, for this moment and this half-typed word.
    ///
    /// `typed` filters before ranking rather than after, so typing "len" narrows
    /// to the lentil dishes even when none of them would have made the top three
    /// unfiltered. Matching is on any word boundary, not just the start of the
    /// name: "soup" should find "lentil soup", because that is the word a person
    /// reaches for.
    public static func suggestions(
        in meals: some Sequence<MealEntry>,
        at moment: Date = Date(),
        typed: String = "",
        limit: Int = 3,
        calendar: Calendar = .current
    ) -> [Entry] {
        guard limit > 0 else { return [] }
        let now = moment.epochMillis
        let daypart = Daypart(at: now, calendar: calendar)
        let all = Array(meals)
        let dayparts = daypartsByDish(in: all, calendar: calendar)

        let needle = typed
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let candidates = entries(in: all).filter { needle.isEmpty || matches($0.name, needle) }

        var ranked: [(entry: Entry, rank: Double)] = []
        ranked.reserveCapacity(candidates.count)
        for entry in candidates {
            let elapsed: Double = Double(max(0, now - entry.lastLoggedAt)) / 86_400_000
            let recency: Double = pow(0.5, elapsed / recencyHalfLifeDays)

            let atThisTime: Int = dayparts[entry.name]?[daypart] ?? 0
            let share: Double = Double(atThisTime) / Double(max(1, entry.timesLogged))
            let affinity: Double = wrongDaypartFloor + (1 - wrongDaypartFloor) * share

            ranked.append((entry, Double(entry.timesLogged) * recency * affinity))
        }

        ranked.sort {
            $0.rank == $1.rank ? $0.entry.lastLoggedAt > $1.entry.lastLoggedAt : $0.rank > $1.rank
        }
        return ranked.prefix(limit).map(\.entry)
    }

    /// True when the needle starts the name or any word inside it. Deliberately
    /// not a fuzzy match: a chip that appears for a typo is a chip you cannot
    /// predict, and an unpredictable shortcut is slower than typing.
    private static func matches(_ name: String, _ needle: String) -> Bool {
        let name = name.lowercased()
        if name.hasPrefix(needle) { return true }
        return name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { $0.hasPrefix(needle) }
    }

    private static func daypartsByDish(
        in meals: [MealEntry],
        calendar: Calendar
    ) -> [String: [Daypart: Int]] {
        var result: [String: [Daypart: Int]] = [:]
        for meal in meals {
            let daypart = Daypart(at: meal.eatenAt, calendar: calendar)
            for dish in meal.storedDishes ?? [] {
                let name = dish.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                result[name, default: [:]][daypart, default: 0] += 1
            }
        }
        return result
    }
}

extension DishLibrary.Entry {
    /// A fresh meal of this dish, logged now, exactly as it was logged last
    /// time. No model call: the ingredients and their weights are already known,
    /// and asking again would spend money to be told the same thing less
    /// reliably.
    ///
    /// Item ids are regenerated for the reason `Recipe.newMeal` regenerates
    /// them — two dinners of the same dish are two events, and sharing item ids
    /// would make the log lie about which one was corrected.
    public func newMeal(eatenAt: EpochMillis = Date().epochMillis, messageID: UUID? = nil) -> MealEntry {
        var dish = lastLogged
        dish.items = dish.items.map {
            MealItem(
                group: $0.group,
                portion: $0.portion,
                label: $0.label,
                grams: $0.grams
            )
        }
        return MealEntry(
            eatenAt: eatenAt,
            items: dish.flattened(),
            source: .recipe,
            storedDishes: [dish],
            messageID: messageID
        )
    }
}
