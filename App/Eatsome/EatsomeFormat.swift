import EatsomeCore
import Foundation

/// How the rewritten screens name and format what they show.
enum EatsomeFormat {
    /// "Tuesday 11 Aug" — the line at the top of the day.
    ///
    /// Assembled rather than pattern-formatted: `.weekday(.wide).day().month(.abbreviated)`
    /// orders by locale and lands on "11 Tuesday Aug" in several of them.
    static func longDay(_ day: Date, calendar: Calendar = .current) -> String {
        let weekday = day.formatted(.dateTime.weekday(.wide))
        let month = day.formatted(.dateTime.month(.abbreviated))
        return "\(weekday) \(calendar.component(.day, from: day)) \(month)"
    }

    /// The clock, in the reader's own 12- or 24-hour convention.
    static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("jm")
        return formatter
    }()

    static func time(_ at: EpochMillis) -> String {
        clock.string(from: Date(epochMillis: at))
    }

    static func whole(_ value: Double) -> String { Int(value.rounded()).formatted() }

    /// Model labels arrive lowercase; a list row wants a capital and a sentence
    /// does not. `localizedCapitalized` would also capitalise "Toast" in
    /// "french toast", which is wrong.
    ///
    /// A function here rather than a `String` extension: the old module exports
    /// one of those, and while both modules are linked an extension in the app
    /// target makes every call site that imports both ambiguous.
    static func capitalizedFirst(_ value: String) -> String {
        guard let first = value.first else { return value }
        return first.uppercased() + value.dropFirst()
    }
}

/// What a stored meal is called in a list.
enum MealTitle {
    /// The dish, not its parts. "French toast" is what you logged; "bread" is
    /// its first ingredient, and an ingredient label naming the card is how a
    /// plate of french toast came to be titled "Bread".
    static func of(_ meal: MealEntry) -> String {
        let names = meal.dishes
            .compactMap { $0.name?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = names.first {
            let title = EatsomeFormat.capitalizedFirst(first)
            return names.count > 1 ? "\(title) +\(names.count - 1)" : title
        }
        if let first = meal.items.map(\.label).first(where: { !$0.isEmpty }) {
            return EatsomeFormat.capitalizedFirst(first)
        }
        return "Meal"
    }

    /// The second line: the clock, then the one fact that most distinguishes
    /// this meal from the others in the list.
    ///
    /// One fact, not all of them. The mock's rows read "19:20 · 36 g protein",
    /// "12:40 · 4 cartons", "07:40 · 65 mg caffeine" — never two — and the
    /// reason is width: this line shares a row with a title and a value, and a
    /// second clause truncates the first. So they are ranked and the winner is
    /// printed.
    ///
    /// The order is by how much the fact narrows down which meal this was. How
    /// many of a thing there were is the most specific; caffeine identifies a
    /// drink; protein is the figure people scan a food list for. Energy is
    /// never here — it is the value on the right.
    static func subtitle(_ meal: MealEntry) -> String {
        var parts = [EatsomeFormat.time(meal.eatenAt)]
        if let fact = distinguishingFact(meal) { parts.append(fact) }
        if meal.eaten != .whole { parts.append(meal.eaten.chipName.lowercased()) }
        return parts.joined(separator: " · ")
    }

    private static func distinguishingFact(_ meal: MealEntry) -> String? {
        // "4 servings" rather than the mock's "4 cartons": a carton is a unit
        // noun and nothing stores one. Inventing a vessel for a count is the
        // kind of small confident wrongness this app is arranged against, and
        // repeating the dish's own name here — "4 × SAVAS milk protein drink"
        // under a title that already says it — is just noise.
        if meal.dishes.count == 1, let dish = meal.dishes.first, dish.count > 1 {
            return "\(dish.count) servings"
        }
        let total = meal.nutrients
        if total.caffeine.rounded() > 0 {
            return "\(EatsomeFormat.whole(total.caffeine)) mg caffeine"
        }
        if total.protein.rounded() > 0 {
            return "\(EatsomeFormat.whole(total.protein)) g protein"
        }
        return nil
    }
}
