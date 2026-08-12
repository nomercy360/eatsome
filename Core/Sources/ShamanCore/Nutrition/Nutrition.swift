import Foundation

/// What a plate is made of, in the five figures `Nutrients` carries.
///
/// This is the one place any of them is computed. `Protein.grams` is a thin
/// accessor onto it rather than a second implementation, because two routes to
/// the same number is how the number starts depending on which screen asked.
///
/// Two ordinary sources, in a fixed order of authority, applied per figure:
///
///   1. a transcribed panel, which is a printed fact and always wins;
///   2. the food table, `grams x per 100 g` for a food named and weighed;
///
/// A broad kind representative is a third source only when the item explicitly
/// records `class_estimate`. A plain miss stays unresolved; it never silently
/// turns a specific food into an arbitrary class average.
///
/// What is *not* a source: a model's estimate. Recognition reports weight and
/// nothing else numeric, exactly as it did when protein was the only figure
/// totalled. A calorie here is a published number multiplied by an observed
/// weight, and is worth precisely what that weight is worth.
public enum Nutrition {
    /// The five figures for a list of foods — a plate, or a dish as described.
    ///
    /// Uses everything on the plate. The per-group portion cap used by meal
    /// summaries has nothing to say about nutrient quantities.
    public static func total(
        in items: [MealItem],
        gramsPerServing: [String: Double] = Protein.defaultGramsPerServing,
        servingGrams: [String: Double] = ServingWeight.defaultGrams,
        foods: FoodNutrientTable? = nil
    ) -> NutrientTotal {
        _ = gramsPerServing
        return items.reduce(into: NutrientTotal.zero) { total, item in
            let servings = item.effectiveServings(servingGrams: servingGrams)
            let weight = item.grams ?? servings * (servingGrams[item.kind.rawValue] ?? 100)

            if let named = foods?.nutrients(in: item) {
                // Table sodium: the salt in the food, not the salt in the
                // cooking. See `Nutrients.saltGrams`.
                total += NutrientTotal(nutrients: named, exactGrams: weight, saltIsFloor: true)
                return
            }

            // A broad representative is opt-in and remains visibly estimated.
            // A plain table miss is unresolved; it must never silently turn
            // mashed potato into mixed vegetables or grilled beef into mince.
            if item.resolution?.status == .classEstimate,
               let representative = foods?.representative(of: item.kind) {
                total += NutrientTotal(
                    nutrients: representative.per100g.forGrams(weight),
                    estimatedGrams: weight,
                    saltIsFloor: true
                )
            } else {
                total += NutrientTotal(unresolvedGrams: weight, saltIsFloor: true)
            }
        }
    }

    /// One dish: what its label said, or what the table implies.
    ///
    /// A printed panel wins figure by figure rather than wholesale. A carton
    /// that prints protein and energy but no sodium contributes two read numbers
    /// and three derived ones, which is the honest reading of that carton — the
    /// alternative is discarding the ingredients over a partial panel, or
    /// discarding the panel over a missing field.
    ///
    /// `size` drops out wherever a panel is present: a packaged serving is
    /// whatever the box holds, so two cartons is twice the printed figure and
    /// "large" says nothing about a 200 ml carton.
    public static func total(
        in dish: MealDish,
        gramsPerServing: [String: Double] = Protein.defaultGramsPerServing,
        servingGrams: [String: Double] = ServingWeight.defaultGrams,
        foods: FoodNutrientTable? = nil
    ) -> NutrientTotal {
        let plate = total(
            in: dish.items,
            gramsPerServing: gramsPerServing,
            servingGrams: servingGrams,
            foods: foods
        )
        // A weighed dish has the whole plate in its ingredients already.
        // Applying the dish multiplier as well is the compounding that made one
        // bowl of ramen worth 126 g of protein — `size` says "large" and so does
        // the ingredient, and the two multiply into four.
        var result = dish.weighed ? plate : plate.scaled(by: dish.multiplier)

        guard let panel = dish.panel else { return result }
        let servings = Double(dish.count)
        if let protein = panel.protein { result.nutrients.protein = protein * servings }
        if let fat = panel.fat { result.nutrients.fat = fat * servings }
        if let carbohydrate = panel.carbohydrate {
            result.nutrients.carbohydrate = carbohydrate * servings
        }
        if let calories = panel.calories { result.nutrients.kcal = calories * servings }
        // Both panel fields are GRAMS — `nutritionPanelSchema` caps each at 100
        // and the Worker derives one from the other in grams — while
        // `Nutrients.sodium` is milligrams, because that is the unit every
        // composition table publishes. The factor of 1000 is the whole reason
        // this is written out rather than assigned: reading the panel in the
        // table's unit put a Monster's sodium at 0.142 mg.
        if let sodium = panel.sodium {
            result.nutrients.sodium = sodium * 1000 * servings
            // Read, not derived. The label settled it, so this dish's salt is a
            // measurement and must not be shown as a lower bound.
            result.saltIsFloor = false
        } else if let salt = panel.salt {
            // Only reached for a panel the Worker never scaled — a hand-entered
            // dish, or one stored before `withSodium` existed. Same definition
            // as `Nutrients.saltGrams`, run the other way.
            result.nutrients.sodium = salt * 1000 / Nutrients.saltPerSodium * servings
            result.saltIsFloor = false
        }
        // A panel that states energy has answered for the whole dish, whatever
        // its ingredients did or did not resolve to. Without this a labelled
        // protein drink would mark the day incomplete because "milk protein" is
        // not a row in the food table.
        if panel.calories != nil {
            result.exactGrams += result.unresolvedGrams + result.estimatedGrams
            result.unresolvedGrams = 0
            result.estimatedGrams = 0
        }
        return result
    }

    /// A plate of dishes — a meal still being composed, with no `MealEntry` yet.
    ///
    /// Not the same as summing `flattened()`: a flat row carries servings and no
    /// panel, so a labelled drink would flatten to whatever its food group is
    /// worth. Anything that shows a figure before the meal is saved has to come
    /// through here, or the number moves when it is saved.
    public static func total(
        in dishes: [MealDish],
        gramsPerServing: [String: Double] = Protein.defaultGramsPerServing,
        servingGrams: [String: Double] = ServingWeight.defaultGrams,
        foods: FoodNutrientTable? = nil
    ) -> NutrientTotal {
        dishes.reduce(into: NutrientTotal.zero) {
            $0 += total(
                in: $1,
                gramsPerServing: gramsPerServing,
                servingGrams: servingGrams,
                foods: foods
            )
        }
    }

    /// One meal, which is the plate above times the share that was eaten — half
    /// a shared dish is half of everything in it.
    public static func total(
        in meal: MealEntry,
        gramsPerServing: [String: Double] = Protein.defaultGramsPerServing,
        servingGrams: [String: Double] = ServingWeight.defaultGrams,
        foods: FoodNutrientTable? = nil
    ) -> NutrientTotal {
        let plate = meal.storedDishes.map {
            total(in: $0, gramsPerServing: gramsPerServing, servingGrams: servingGrams, foods: foods)
        } ?? total(
            in: meal.items,
            gramsPerServing: gramsPerServing,
            servingGrams: servingGrams,
            foods: foods
        )
        return plate.scaled(by: meal.eaten.factor)
    }

    /// A day, a week, or anything else a list of meals stands for.
    public static func total(
        in meals: [MealEntry],
        gramsPerServing: [String: Double] = Protein.defaultGramsPerServing,
        servingGrams: [String: Double] = ServingWeight.defaultGrams,
        foods: FoodNutrientTable? = nil
    ) -> NutrientTotal {
        meals.reduce(into: NutrientTotal.zero) {
            $0 += total(
                in: $1,
                gramsPerServing: gramsPerServing,
                servingGrams: servingGrams,
                foods: foods
            )
        }
    }
}
