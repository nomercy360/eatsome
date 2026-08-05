import Foundation

/// The 14 items said the way a person would say them.
///
/// `MedasItem.title` is the screener's own phrasing — "Fish or seafood ≥ 3
/// servings/week" — which is exactly right in a methods note and exactly wrong
/// on a screen someone reads before lunch. The two live apart so the honest
/// definition never has to be softened to make a card read well.
///
/// Kept in Core, next to the rule it describes: an item whose threshold moves
/// and whose sentence does not is a screen that lies.
public enum MedasCopy {
    public static func plainTitle(_ id: Int) -> String {
        switch id {
        case 1: "You cook with olive oil"
        case 2: "Olive oil, most days"
        case 3: "Vegetables, twice a day"
        case 4: "Fruit, three a day"
        case 5: "Red and cured meat"
        case 6: "Butter and cream"
        case 7: "Fizzy and sweet drinks"
        case 9: "Beans or lentils, 3 a week"
        case 10: "Fish or seafood"
        case 11: "Cakes and pastry"
        case 12: "Nuts"
        case 13: "You choose chicken and fish"
        case 14: "Tomato & onion base"
        default: Medas.items.first { $0.id == id }?.title ?? "Item \(id)"
        }
    }

    /// The bare food, for use inside a sentence about the week.
    ///
    /// `plainTitle` carries its own qualifier — "Beans or lentils, 3 a week" —
    /// which is right on a row with a progress bar and wrong in the middle of
    /// "…and fish are what the week is missing."
    public static func foodNoun(_ id: Int) -> String? {
        switch id {
        case 2: "olive oil"
        case 3: "vegetables"
        case 4: "fruit"
        case 9: "beans"
        case 10: "fish"
        case 12: "nuts"
        case 14: "a tomato base"
        default: nil
        }
    }

    /// What would clear this item, in servings you could picture.
    ///
    /// Nil where the title already says everything, and nil for the two habits
    /// and every upper bound: "eat less cake" is not a next step, it is a
    /// scolding, and the design puts those items under a heading that says you
    /// are already doing fine.
    public static func advice(for item: MedasResult.ItemResult) -> String? {
        guard !item.passed, !item.isUpperBound else { return nil }
        let short = Int(max(0, (item.target - item.observed)).rounded(.up))

        switch item.id {
        case 2:
            return "Cooking with it counts, and so does what you pour on a salad."
        case 3:
            return short <= 1
                ? "One more plate with something green on it."
                : "\(spell(short)) more plates with something green on them."
        case 9:
            return short <= 1
                ? "One more bowl of beans or lentils this week."
                : "\(spell(short)) more bowls of beans or lentils this week."
        case 10:
            return short <= 1
                ? "One more meal with fish would clear it."
                : "\(spell(short)) more meals with fish would clear it."
        case 12:
            return short <= 1
                ? "A handful counts. One handful left this week."
                : "A handful counts. \(spell(short)) handfuls left this week."
        case 14:
            return "Sofrito — the tomato, onion and garlic base most stews start with."
        default:
            return nil
        }
    }

    /// How far along the item is, in its own unit — a fraction for the bar and
    /// the "1 of 3" beside it.
    ///
    /// Daily items are reported by the scorer as an average per day, which is
    /// the right number for the rule and the wrong one for a progress bar: "1.4
    /// of 3" reads as arithmetic, where "4 of 7 days" reads as a week. Pass the
    /// day count for those and they measure in days instead.
    public static func measure(for item: MedasResult.ItemResult, daysMet: Int?, windowDays: Int) -> Measure {
        if let daysMet {
            return Measure(
                fraction: windowDays > 0 ? Double(daysMet) / Double(windowDays) : 0,
                text: "\(daysMet) of \(windowDays) days"
            )
        }
        let target = max(item.target, 0.01)
        return Measure(
            fraction: min(1, item.observed / target),
            text: "\(number(item.observed)) of \(number(item.target))"
        )
    }

    public struct Measure: Sendable, Hashable {
        public let fraction: Double
        public let text: String
    }

    /// Small counts read better as words in a sentence and as digits in a
    /// measure; this is the sentence half.
    private static func spell(_ value: Int) -> String {
        switch value {
        case 2: "Two"
        case 3: "Three"
        case 4: "Four"
        case 5: "Five"
        default: "\(value)"
        }
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))"
            : value.formatted(.number.precision(.fractionLength(1)))
    }
}
