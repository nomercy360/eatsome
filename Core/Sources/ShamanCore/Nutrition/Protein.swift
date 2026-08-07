import Foundation

/// Protein in grams, and the group table it falls back to.
///
/// Protein was the only macronutrient this app counted for its first three
/// years, on the argument that it was the only one a photograph could estimate:
/// its sources are discrete and countable — an egg, a fillet, a pot of yoghurt —
/// where fat is smeared through a dish and invisible in the cooking. Energy was
/// refused outright, because a model asked for calories from the look of a plate
/// returns a figure with 30–50% error that is indistinguishable from data.
///
/// What changed is not that opinion but the input. Recognition reports weight,
/// and `FoodNutrientTable` turns a weight and a name into a published figure, so
/// energy is now arrived at the same way protein always was and is worth
/// whatever the weight is worth. Nothing asks a model for a calorie. See
/// `Nutrition`, which computes all five and which this type now delegates to.
///
/// Protein keeps its own name and its own group table because it is the figure
/// with a history: every estimate ever shown was scored against
/// `defaultGramsPerServing`, and `pnpm eval:nutrients` measures changes to it.
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
    /// Every overload below reads the protein figure off `Nutrition`, which is
    /// the only place any of the five is computed. They stay because protein is
    /// what most of the app asks for and `Nutrition.total(...).nutrients.protein`
    /// at forty call sites reads worse than this does, not because they do
    /// anything of their own.
    ///
    /// The contract they document is still the contract: `foods` is consulted
    /// first and only ever for a weighed, labelled item, and everything else
    /// falls through to the group table. A food the table has never heard of
    /// must cost what it cost before the table existed, never zero.
    public static func grams(
        in items: [MealItem],
        gramsPerServing: [String: Double] = defaultGramsPerServing,
        foods: FoodNutrientTable? = nil
    ) -> Double {
        Nutrition.total(in: items, gramsPerServing: gramsPerServing, foods: foods).nutrients.protein
    }

    /// Grams in one dish: what the label said, or what the table implies.
    ///
    /// A transcribed panel is a fact and wins; everything else is estimated from
    /// food groups, which is why nothing stores the estimate — retuning the
    /// table in `shaman-config.json` moves every derived figure in the history,
    /// and must move none of the measured ones.
    public static func grams(
        in dish: MealDish,
        gramsPerServing: [String: Double] = defaultGramsPerServing,
        foods: FoodNutrientTable? = nil
    ) -> Double {
        Nutrition.total(in: dish, gramsPerServing: gramsPerServing, foods: foods).nutrients.protein
    }

    /// Grams across a plate of dishes — a meal that is still being composed and
    /// has no `MealEntry` yet.
    ///
    /// Not the same as summing `flattened()`: a flat row carries servings and
    /// no panel, so a labelled drink flattens to whatever its food group is
    /// worth. Anything that shows a figure before the meal is saved has to come
    /// through here, or the number moves when it is saved.
    public static func grams(
        in dishes: [MealDish],
        gramsPerServing: [String: Double] = defaultGramsPerServing,
        foods: FoodNutrientTable? = nil
    ) -> Double {
        Nutrition.total(in: dishes, gramsPerServing: gramsPerServing, foods: foods).nutrients.protein
    }

    /// Grams in one meal, which is the plate above times the share you ate —
    /// half a shared dish is half the protein.
    public static func grams(
        in meal: MealEntry,
        gramsPerServing: [String: Double] = defaultGramsPerServing,
        foods: FoodNutrientTable? = nil
    ) -> Double {
        Nutrition.total(in: meal, gramsPerServing: gramsPerServing, foods: foods).nutrients.protein
    }

    public static func grams(
        in meals: [MealEntry],
        gramsPerServing: [String: Double] = defaultGramsPerServing,
        foods: FoodNutrientTable? = nil
    ) -> Double {
        Nutrition.total(in: meals, gramsPerServing: gramsPerServing, foods: foods).nutrients.protein
    }
}
