import EatsomeCore
import Foundation

/// The logic behind the meal detail, kept out of the views so each rule is
/// stated once and can be read without SwiftUI around it.
///
/// Every mutation here goes through a stored, priced value — a `FoodSize`, a
/// `FoodAlternative`, `MealDish.scaled(toCount:)` — so a change on the detail
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
        if let size = chosenSize(of: item, count: dish.count) { text += ", \(size.label)" }
        if dish.count > 1 { text += " × \(dish.count)" }
        return text
    }

    /// The size whose weight matches the row, if the row is a menu item with
    /// sizes. A row's grams are absolute across every serving, so the match is
    /// against `size.grams × count`.
    static func chosenSize(of item: MealItem, count: Int) -> FoodSize? {
        guard item.isMenuItem, !item.sizes.isEmpty else { return nil }
        let perServing = item.grams / Double(max(1, count))
        return item.sizes.min { abs($0.grams - perServing) < abs($1.grams - perServing) }
            .flatMap { abs($0.grams - perServing) < 0.5 ? $0 : nil }
    }

    /// True when the row is a menu item the person has not yet chosen a size
    /// or a rival for. Only meaningful before saving: saving is never blocked
    /// on answering, and once saved the row is what it is.
    static func needsPick(_ item: MealItem) -> Bool {
        item.isMenuItem && (item.sizes.count > 1 || !item.alternatives.isEmpty)
    }

    // MARK: Applying a pick

    /// The row with a size chosen: that size's weight for every serving, and
    /// that size's composition. Stamped `.user` — the person chose it — and
    /// the sizes list is kept, because choosing one size does not retire the
    /// others.
    static func applying(size: FoodSize, to item: MealItem, count: Int) -> MealItem {
        var copy = item
        copy.grams = size.grams * Double(max(1, count))
        copy.per100g = size.per100g
        copy.provenance = .user
        return copy
    }

    /// The row replaced by a rival: its name, its composition, **and its
    /// weight**. The shortlist is kept so the person can change their mind
    /// again; the sizes are dropped, because they were the old product's.
    /// Stamped `.user`.
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
        copy.sizes = []
        copy.provenance = .user
        return copy
    }

    /// One dish with the rival, the count and the size applied — in that order,
    /// and the order is load-bearing.
    ///
    /// A rival's weight is what the model weighed *at the count it recognised*,
    /// so it has to replace the food before `scaled(toCount:)` rewrites the
    /// weights, or a count the person already changed would be silently undone.
    /// A size is last because it is the most specific claim there is: a
    /// published weight per serving, multiplied by the servings present, which
    /// overrides both.
    ///
    /// Share is not here: on a one-dish meal it belongs to the meal, on a mixed
    /// meal to the dish, and the caller knows which.
    static func applying(
        count: Int,
        size: FoodSize?,
        alternative: FoodAlternative?,
        to dish: MealDish
    ) -> MealDish {
        var copy = dish
        if let alternative, let first = copy.items.first {
            copy.items[0] = applying(alternative: alternative, to: first)
        }
        copy = copy.scaled(toCount: count)
        if let size, let first = copy.items.first {
            copy.items[0] = applying(size: size, to: first, count: copy.count)
        }
        return copy
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

