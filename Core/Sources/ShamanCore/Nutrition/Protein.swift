import Foundation

/// Protein in grams, read from the same composition result as every nutrient.
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
/// Protein keeps its own name because it is the figure with the longest product
/// history and many UI call sites still ask for it directly.
public enum Protein {
    /// Grams of protein in one serving of each group, where a serving is the
    /// same adult portion `Portion.medium` means everywhere else.
    ///
    /// These are coarse by construction — one number for "fish" covers cod and
    /// mackerel — and they are meant to be edited in `shaman-config.json` rather
    /// than argued with in Swift. Per meal the error is large; summed over a day
    /// of countable sources it lands close enough to see whether you are near a
    /// target or nowhere near it.
    /// Retained as an API/config compatibility slot. Broad kind-level protein
    /// estimates are no longer applied automatically; protein comes from the
    /// same exact composition record as the other nutrients.
    public static let defaultGramsPerServing: [String: Double] = [:]

    /// What a day should reach, from body weight and how hard you are training.
    /// Grams in a list of foods — a plate, or a dish as it is described.
    ///
    /// Every overload below reads the protein figure off `Nutrition`, which is
    /// the only place any of the five is computed. They stay because protein is
    /// what most of the app asks for and `Nutrition.total(...).nutrients.protein`
    /// at forty call sites reads worse than this does, not because they do
    /// anything of their own.
    ///
    /// `foods` resolves a named composition row. A miss returns zero here while
    /// `Nutrition.total` carries its weight in `unresolvedGrams`, so callers
    /// presenting totals can say why the figure is incomplete.
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
    /// named foods. Resolution provenance is stored on meal items so an exact
    /// match and a broad estimate can never look identical.
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
    /// no panel. Anything that shows a figure before the meal is saved has to come
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
