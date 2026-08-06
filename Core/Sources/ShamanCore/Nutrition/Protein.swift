import Foundation

/// Protein in grams — the one macronutrient this app counts, and the one
/// exception to the no-grams rule.
///
/// It earns the exception on three grounds. It is the only macro with a
/// threshold worth hitting rather than a ratio worth watching: roughly 1.6–2.2 g
/// per kilogram of body weight a day when you are building muscle, which is an
/// absolute number and therefore has to be summed in grams. It is the only one a
/// photograph can estimate tolerably, because its sources are discrete and
/// countable — an egg, a fillet, a pot of yoghurt — where fat is smeared through
/// a dish and invisible in the cooking. And its target is computable from data
/// already here: body weight arrives from HealthKit.
///
/// Carbohydrate and fat deliberately get no daily gram target. That is the path
/// that ends with a calorie counter, which is the thing this app exists not to
/// be. Nothing anywhere converts any of this to kilocalories.
public enum Protein {
    /// Grams of protein in one serving of each group, where a serving is the
    /// same adult portion `Portion.medium` means everywhere else.
    ///
    /// These are coarse by construction — one number for "fish" covers cod and
    /// mackerel — and they are meant to be edited in `shaman-config.json` rather
    /// than argued with in Swift. Per meal the error is large; summed over a day
    /// of countable sources it lands close enough to see whether you are near a
    /// target or nowhere near it.
    public static let defaultGramsPerServing: [String: Double] = [
        FoodGroup.fish.rawValue: 22,
        FoodGroup.whiteMeat.rawValue: 26,
        FoodGroup.redMeat.rawValue: 24,
        FoodGroup.processedMeat.rawValue: 14,
        FoodGroup.egg.rawValue: 6,
        FoodGroup.dairy.rawValue: 8,
        FoodGroup.legumes.rawValue: 8,
        FoodGroup.nuts.rawValue: 5,
        FoodGroup.wholeGrains.rawValue: 4,
        FoodGroup.refinedGrains.rawValue: 3,
        FoodGroup.vegetables.rawValue: 2,
        FoodGroup.fruit.rawValue: 0.5,
        FoodGroup.healthyFats.rawValue: 1.5,
        FoodGroup.pastry.rawValue: 4,
        FoodGroup.sweets.rawValue: 2,
        FoodGroup.sofrito.rawValue: 1,
        FoodGroup.butter.rawValue: 0.5,
        FoodGroup.oliveOil.rawValue: 0,
        FoodGroup.sugaryDrinks.rawValue: 0,
        FoodGroup.alcohol.rawValue: 0,
        // Calibrated against dairy, where one serving is about 200 ml of milk.
        // Black coffee and unsweetened tea round to nothing. Plant milk spans
        // oat at about 1 g to soy at about 7 g, so this is a midpoint and the
        // least certain figure in the table.
        FoodGroup.coffee.rawValue: 0,
        FoodGroup.tea.rawValue: 0,
        FoodGroup.juice.rawValue: 1,
        FoodGroup.plantMilk.rawValue: 3,
        FoodGroup.smoothie.rawValue: 2,
        // Zero, because `other` is the bucket for food that was not recognised
        // and a number here is invented rather than estimated. It read 2 g,
        // which is how a black coffee came to be worth 2 g of protein. Under-
        // reporting an unrecognised food is recoverable — the person can name
        // it — while a figure the app made up is not visible as a mistake.
        FoodGroup.other.rawValue: 0
    ]

    /// What a day should reach, from body weight and how hard you are training.
    public enum Intent: String, Codable, Sendable, CaseIterable {
        case maintain
        case active
        case building

        /// Grams per kilogram of body weight per day.
        public var gramsPerKilogram: Double {
            switch self {
            case .maintain: 1.2
            case .active: 1.6
            case .building: 2.0
            }
        }

        public var displayName: String {
            switch self {
            case .maintain: "Maintain"
            case .active: "Active"
            case .building: "Building"
            }
        }
    }

    public static func dailyTarget(weightKilograms: Double, intent: Intent) -> Double {
        (weightKilograms * intent.gramsPerKilogram).rounded()
    }

    /// Grams in a list of foods — a plate, or a dish as it is described.
    ///
    /// Uses what is on the plate rather than what the MEDAS scorer counts: the
    /// per-group cap exists to stop a platter clearing a diet target, and has
    /// nothing to say about protein you actually ate.
    public static func grams(in items: [MealItem], gramsPerServing: [String: Double] = defaultGramsPerServing) -> Double {
        items.reduce(0.0) { total, item in
            total + (gramsPerServing[item.group.rawValue] ?? 0) * item.effectiveServings
        }
    }

    /// Grams in one dish: what the label said, or what the table implies.
    ///
    /// One number out, from either of two kinds of input. A transcribed panel
    /// is a fact and wins; everything else is estimated from food groups, which
    /// is why nothing stores the estimate — retuning the table in
    /// `shaman-config.json` moves every derived figure in the history, and must
    /// move none of the measured ones.
    ///
    /// `size` drops out when a panel is present: a packaged serving is whatever
    /// the box holds, so two cartons is twice the printed figure and "large"
    /// says nothing about a 200 ml carton.
    public static func grams(in dish: MealDish, gramsPerServing: [String: Double] = defaultGramsPerServing) -> Double {
        if let confirmed = dish.panel?.protein { return confirmed * Double(dish.count) }
        return grams(in: dish.items, gramsPerServing: gramsPerServing) * dish.multiplier
    }

    /// Grams across a plate of dishes — a meal that is still being composed and
    /// has no `MealEntry` yet.
    ///
    /// Not the same as summing `flattened()`: a flat row carries servings and
    /// no panel, so a labelled drink flattens to whatever its food group is
    /// worth. Anything that shows a figure before the meal is saved has to come
    /// through here, or the number moves when it is saved.
    public static func grams(in dishes: [MealDish], gramsPerServing: [String: Double] = defaultGramsPerServing) -> Double {
        dishes.reduce(0.0) { $0 + grams(in: $1, gramsPerServing: gramsPerServing) }
    }

    /// Grams in one meal, which is the plate above times the share you ate —
    /// half a shared dish is half the protein.
    public static func grams(in meal: MealEntry, gramsPerServing: [String: Double] = defaultGramsPerServing) -> Double {
        let plate = meal.storedDishes.map { grams(in: $0, gramsPerServing: gramsPerServing) }
            ?? grams(in: meal.items, gramsPerServing: gramsPerServing)
        return plate * meal.eaten.factor
    }

    public static func grams(in meals: [MealEntry], gramsPerServing: [String: Double] = defaultGramsPerServing) -> Double {
        meals.reduce(0) { $0 + grams(in: $1, gramsPerServing: gramsPerServing) }
    }
}
