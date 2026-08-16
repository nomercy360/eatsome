import EatsomeCore
import Foundation

/// The logic behind the meal detail, kept out of the views so each rule is
/// stated once and can be read without SwiftUI around it.
///
/// Every mutation here goes through a stored, priced value — a `FoodForkOption`,
/// a `FoodAlternative`, `MealDish.scaled(toCount:)` — so a change on the detail
/// screen re-prices by construction. There is no path that renames a food and
/// leaves its composition behind, because there is no path that takes a name
/// without a composition beside it.
enum MealDetailModel {
    /// The one thing every frame prints under the figures: what was priced,
    /// and how. "Estimated · Italian B.M.T., 6-inch × 2".
    ///
    /// The mock draws only "Estimated", because grounded recognition returns
    /// no citation and `.model` is the only source those frames can show. The
    /// other two words are for cases the mock does not draw and are the
    /// plainest available: a figure read off a label is *from the label*, a
    /// figure a person entered or chose is *corrected*. If any figure on the
    /// plate is stronger than the model's, the line says so, because the
    /// weaker word would be a lie about the stronger figure.
    static func provenanceLine(_ meal: MealEntry, resolved: Bool = true) -> String {
        let sources = Set(meal.provenance)
        let word: String
        if sources.contains(.user) { word = "Corrected" }
        else if sources.contains(.panel) { word = "From the label" }
        else { word = "Estimated" }
        let what = pricedDescription(meal)
        let tail = resolved ? "" : " — the pick below decides"
        return what.isEmpty ? word : "\(word) · \(what)\(tail)"
    }

    /// "Italian B.M.T., 6-inch × 2" for one dish; "3 items" for several.
    static func pricedDescription(_ meal: MealEntry) -> String {
        guard meal.dishes.count == 1, let dish = meal.dishes.first else {
            return meal.dishes.isEmpty ? "" : "\(meal.dishes.count) items"
        }
        guard let item = dish.items.first, dish.items.count == 1 else {
            return dish.name.map(EatsomeFormat.capitalizedFirst) ?? "\(dish.items.count) ingredients"
        }
        var text = EatsomeFormat.capitalizedFirst(item.label)
        // The default the person did not choose is not printed as if they had:
        // "Caffè latte, Tall" beside "Estimated" reads as a claim. A stated,
        // seen or answered fork's word is theirs and goes on the line.
        if let word = item.forks.first(where: { $0.chosenFrom != .assumed })?.chosen?.label {
            text += ", \(word)"
        }
        if dish.count > 1 { text += " × \(dish.count)" }
        return text
    }

    /// Whether the detail should offer chips at all: any fork with something
    /// to choose, or a menu item with rivals.
    static func hasPick(_ item: MealItem) -> Bool {
        item.forks.contains { $0.options.count > 1 } || (item.isMenuItem && !item.alternatives.isEmpty)
    }

    /// True when the row carries a question worth putting to the person before
    /// saving: an open fork (`MealItem.openForks` — assumed, and wide enough to
    /// matter), or a menu item with rivals. Only meaningful before saving:
    /// saving is never blocked on answering, and once saved the row is what it is.
    static func needsPick(_ item: MealItem) -> Bool {
        !item.openForks.isEmpty || (item.isMenuItem && !item.alternatives.isEmpty)
    }

    /// The fork the detail asks about first, when it asks: the widest open one.
    static func askedFork(_ item: MealItem) -> FoodFork? { item.openForks.first }

    // MARK: Applying a pick

    /// The row with one fork answered: that option's weight and composition,
    /// stamped `.user` — the person chose it — and the fork kept with the
    /// answer marked, so they can change their mind again.
    ///
    /// The row's *other* forks are dropped. Each of their options was priced
    /// as a whole-row answer against the row as it stood — a milk fork's "oat"
    /// is 207 kcal for a Tall — and after this the row is a Grande. Keeping
    /// them would offer numbers that look chosen and are not, which is the
    /// rename-cannot-re-price rule one level down; the model prices forks per
    /// row, not per combination, and the pick sheet asks one thing at a time.
    static func applying(option: FoodForkOption, of fork: FoodFork, to item: MealItem) -> MealItem {
        var copy = item
        copy.grams = option.grams
        copy.per100g = option.per100g
        copy.provenance = .user
        copy.forks = [fork.choosing(option)]
        return copy
    }

    /// The row replaced by a rival: its name, its composition, **and its
    /// weight**. The shortlist is kept so the person can change their mind
    /// again; the forks are dropped, because they were priced for the old
    /// food. Stamped `.user`.
    ///
    /// The weight moves with the rest and that is the whole point. A rival is
    /// rarely the same size as the first answer, so keeping the old grams
    /// prices a tuna sub by what the turkey sub weighed — a number that looks
    /// chosen and is not. Everything a swap touches, it restates.
    static func applying(alternative: FoodAlternative, to item: MealItem) -> MealItem {
        var copy = item
        copy.label = alternative.label
        copy.per100g = alternative.per100g
        copy.grams = alternative.grams
        copy.forks = []
        copy.provenance = .user
        return copy
    }

    /// A fork and one of its options, as picked on a sheet.
    struct ForkPick: Equatable {
        let fork: FoodFork
        let option: FoodForkOption
    }

    /// One dish with the rival, or the fork answer, and the count applied.
    ///
    /// A rival and an option are both whole-row answers priced *at the count
    /// the model recognised* — the shortlist and the forks scale with the row
    /// in `scaled(toCount:)` — so either replaces the food before the count
    /// rewrites the weights, or a count the person already changed would be
    /// silently undone. They are exclusive: an alternative retires the forks
    /// (priced for the old food), so a sheet offers one or the other pick.
    ///
    /// Share is not here: on a one-dish meal it belongs to the meal, on a mixed
    /// meal to the dish, and the caller knows which.
    static func applying(
        count: Int,
        pick: ForkPick?,
        alternative: FoodAlternative?,
        to dish: MealDish
    ) -> MealDish {
        var copy = dish
        if let alternative, let first = copy.items.first {
            copy.items[0] = applying(alternative: alternative, to: first)
        } else if let pick, let first = copy.items.first {
            copy.items[0] = applying(option: pick.option, of: pick.fork, to: first)
        }
        return copy.scaled(toCount: count)
    }

    /// Energy for one serving of a dish: what "103 kcal each" means.
    static func perServingKcal(_ dish: MealDish) -> Double {
        var whole = dish
        whole.share = nil
        return whole.nutrients.kcal / Double(max(1, dish.count))
    }

    /// The meal with one dish replaced and marked corrected. Nothing else moves.
    static func replacing(_ dish: MealDish, in meal: MealEntry) -> MealEntry {
        var copy = meal
        if let index = copy.dishes.firstIndex(where: { $0.id == dish.id }) {
            copy.dishes[index] = dish
        }
        copy.wasCorrected = true
        return copy
    }
}

/// The five figures every frame prints, in the mock's order.
struct MealFigure: Identifiable {
    let name: String
    let value: Double
    let unit: String
    /// How the value is printed. Salt is the one with a decimal.
    let decimals: Int

    var id: String { name }
    var text: String { "\(value.formatted(.number.precision(.fractionLength(0...decimals)))) \(unit)" }
    var spoken: String {
        let unitWord = switch unit {
        case "kcal": "kilocalories"
        case "g": "grams"
        default: unit
        }
        return "\(name) \(value.formatted(.number.precision(.fractionLength(0...decimals)))) \(unitWord)"
    }
    /// A displayed zero keeps its column and stops competing.
    var isZero: Bool { value.rounded() == 0 && decimals == 0 || (decimals > 0 && value < 0.05) }

    static func figures(_ nutrients: Nutrients) -> [MealFigure] {
        [
            MealFigure(name: "Energy", value: nutrients.kcal, unit: "kcal", decimals: 0),
            MealFigure(name: "Protein", value: nutrients.protein, unit: "g", decimals: 0),
            MealFigure(name: "Carbs", value: nutrients.carbohydrate, unit: "g", decimals: 0),
            MealFigure(name: "Fat", value: nutrients.fat, unit: "g", decimals: 0),
            MealFigure(name: "Salt", value: nutrients.saltGrams, unit: "g", decimals: 1),
        ]
    }
}

