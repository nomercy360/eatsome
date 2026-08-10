import Foundation

/// Every rule said the way a person would say it.
///
/// `DietGoal.title` is the screener's own phrasing — "Fish or seafood ≥ 3
/// servings/week" — which is exactly right in a methods note and exactly wrong
/// on a card someone reads before lunch. The two lived apart already; what
/// changed is where the plain half comes from.
///
/// It used to be a `switch` on fourteen MEDAS item ids, which worked for exactly
/// as long as there were fourteen items and no others. A diet somebody assembles
/// from steppers has rules nobody wrote a sentence for, and a screen that falls
/// back to "≥ 3 servings/week" for those is a screen that reads like a form for
/// custom diets and like an app for the built-in one. So the sentence is
/// generated from the rule's *template* — its shape, its groups and its
/// threshold — and `plainTitle` overrides it where a hand-written line already
/// reads better, which is most of MEDAS and none of anything else.
public enum DietCopy {
    /// The row title on My week and in the editor.
    public static func plainTitle(_ goal: DietGoal, in spec: DietSpec? = nil) -> String {
        if let written = goal.plainTitle { return written }
        return generated(goal.shape, in: spec)
    }

    public static func plainTitle(_ goal: DietResult.GoalResult, in spec: DietSpec? = nil) -> String {
        if let written = goal.plainTitle { return written }
        return generated(goal.shape, in: spec)
    }

    private static func generated(_ shape: DietGoal.Shape, in spec: DietSpec?) -> String {
        switch shape {
        case .dailyAtLeast(let groups, let target):
            "\(names(groups)), \(times(target)) a day"
        case .weeklyAtLeast(let groups, let target):
            "\(names(groups)), \(times(target)) a week"
        // An upper bound is titled with the food alone. "Cakes and pastry, less
        // than three a week" is a rule; "Cakes and pastry" under a heading that
        // says you are keeping these low is a person being told they are doing
        // fine, and the count sits at the end of the row where it belongs.
        case .dailyBelow(let groups, _), .weeklyBelow(let groups, _):
            names(groups)
        case .eachMeal(let groups):
            "\(names(groups)) at every meal"
        case .dailyAtLeastGrams(let nutrient, let target):
            "\(nutrient.displayName), \(Int(target.rounded())) \(nutrient.unit) a day"
        case .habit(let id):
            spec?.habits.first { $0.id == id }?.question ?? "A question about how you cook"
        }
    }

    /// Group names joined as a person would say them, sentence-cased.
    ///
    /// Capped at three for the same reason `OliveRating.reason` caps: past three
    /// the line stops being a sentence and becomes the list the sentence was
    /// meant to replace.
    private static func names(_ groups: [FoodGroup]) -> String {
        let names = groups.prefix(3).map(\.shortName)
        let joined: String = switch names.count {
        case 0: "Food"
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1].lowercased()
        }
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private static func times(_ value: Double) -> String {
        switch value {
        case 1: "once"
        case 2: "twice"
        case 3: "three"
        case 4: "four"
        case 5: "five"
        default:
            value == value.rounded()
                ? "\(Int(value))"
                : value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    /// The bare food, for use inside a sentence about the week: "…and fish are
    /// what the week is missing."
    ///
    /// Nil for a rule with no single food to name — a habit, a nutrient, or an
    /// upper bound, where the sentence would be about avoiding something.
    public static func foodNoun(_ goal: DietResult.GoalResult) -> String? {
        guard !goal.isUpperBound else { return nil }
        let groups = goal.shape.groups
        guard !groups.isEmpty else { return nil }
        return groups.prefix(2).map(\.sentenceName).joined(separator: " and ")
    }

    /// What would clear this rule, in helpings you could picture.
    ///
    /// Nil for every upper bound and every habit: "eat less cake" is not a next
    /// step, it is a scolding, and the design puts those rules under a heading
    /// that says you are already doing fine.
    public static func advice(for goal: DietResult.GoalResult) -> String? {
        guard !goal.passed, !goal.isUpperBound, !goal.isHabit else { return nil }

        switch goal.shape {
        case .eachMeal(let groups):
            return "\(names(groups)) with every meal, not just the big ones."

        case .dailyAtLeastGrams(let nutrient, _):
            let short = Int(max(0, goal.target - goal.observed).rounded())
            guard short > 0 else { return nil }
            return "About \(short) g of \(nutrient.displayName.lowercased()) short a day — "
                + "a pot of yoghurt or an egg closes most of that."

        case .dailyAtLeast(let groups, _), .weeklyAtLeast(let groups, _):
            let short = Int(max(0, goal.target - goal.observed).rounded(.up))
            guard let group = groups.first else { return nil }
            let cadence: String = if case .weeklyAtLeast = goal.shape { " this week" } else { "" }
            let helping = group.helping(short)
            return short <= 1
                ? "One more \(helping)\(cadence)."
                : "\(Count.spell(short)) more \(helping)\(cadence)."

        default:
            return nil
        }
    }

    /// How far along the rule is, in its own unit — a fraction for the bar and
    /// the "1 of 3" beside it.
    ///
    /// Daily rules are reported by the scorer as an average per day, which is
    /// the right number for the rule and the wrong one for a progress bar: "1.4
    /// of 3" reads as arithmetic, where "4 of 7 days" reads as a week. Pass the
    /// day count for those and they measure in days instead.
    public static func measure(for goal: DietResult.GoalResult, daysMet: Int?, windowDays: Int) -> Measure {
        if let daysMet {
            return Measure(
                fraction: windowDays > 0 ? Double(daysMet) / Double(windowDays) : 0,
                text: "\(daysMet) of \(windowDays) days"
            )
        }
        if case .eachMeal = goal.shape {
            // `observed` is already the fraction of meals that carried it, so a
            // percentage would be the honest reading and a fraction of meals is
            // the readable one.
            return Measure(fraction: goal.observed, text: "\(Int((goal.observed * 100).rounded()))% of meals")
        }
        let target = max(goal.target, 0.01)
        return Measure(
            fraction: min(1, goal.observed / target),
            text: "\(number(goal.observed)) of \(number(goal.target))"
        )
    }

    public struct Measure: Sendable, Hashable {
        public let fraction: Double
        public let text: String
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))"
            : value.formatted(.number.precision(.fractionLength(1)))
    }
}

extension FoodGroup {
    /// One helping of this food, said as the thing you would carry to a table.
    ///
    /// "One more bowl of beans or lentils" is a next step; "one more serving of
    /// legumes" is a unit of measurement. This is the per-group half of what
    /// used to be fourteen hand-written pieces of advice — it generalizes,
    /// because a helping of nuts is a handful whichever diet asked for it.
    public func helping(_ count: Int) -> String {
        let plural = count != 1
        switch self {
        case .vegetables: return plural ? "plates with something green on them" : "plate with something green on it"
        case .fruit: return plural ? "pieces of fruit" : "piece of fruit"
        case .legumes: return plural ? "bowls of beans or lentils" : "bowl of beans or lentils"
        case .fish: return plural ? "meals with fish" : "meal with fish"
        case .nuts: return plural ? "handfuls of nuts" : "handful of nuts"
        case .oliveOil: return plural ? "dishes cooked or dressed in olive oil" : "dish cooked or dressed in olive oil"
        case .wholeGrains: return plural ? "meals on whole grains" : "meal on whole grains"
        case .plantFats: return plural ? "servings of avocado, olives or seeds" : "serving of avocado, olives or seeds"
        case .cookedTomatoSauce: return plural ? "dishes on a tomato and onion base" : "dish on a tomato and onion base"
        case .whiteMeat, .redMeat, .processedMeat, .egg, .dairy:
            return plural ? "meals with \(sentenceName)" : "meal with \(sentenceName)"
        default:
            return plural ? "servings of \(sentenceName)" : "serving of \(sentenceName)"
        }
    }
}

/// Small numbers are words in this app's sentences — "Three meals", "Six of the
/// last seven days" — because a digit mid-sentence reads as data and the point
/// of the sentence is that it is not.
///
/// In Core rather than in the design system because the advice lines above are
/// written here, next to the rules they describe, and a sentence that spells its
/// numbers in one file and prints them in another is two voices.
public enum Count {
    public static func spell(_ value: Int, capitalized: Bool = true) -> String {
        // Up to twenty, because the number this is most often asked to spell is
        // a count of rules, and a diet somebody builds can have more of them
        // than a screener does. Past twenty a digit is what a person would write
        // too.
        let words = ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven",
                     "Eight", "Nine", "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen",
                     "Fifteen", "Sixteen", "Seventeen", "Eighteen", "Nineteen", "Twenty"]
        guard value >= 0, value < words.count else { return "\(value)" }
        return capitalized ? words[value] : words[value].lowercased()
    }

    public static func meals(_ value: Int) -> String {
        value == 1 ? "One meal" : "\(spell(value)) meals"
    }
}
