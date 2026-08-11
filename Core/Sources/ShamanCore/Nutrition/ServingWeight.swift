/// What one display serving of each food group weighs.
///
/// Recognition now reports grams — the edible weight of an ingredient as it sits
/// on the plate — because a photograph shows an amount of food, not an amount of
/// "serving". This is the table that turns that observation into the unit the
/// meal summaries and ratings are made of.
///
/// Two things it deliberately is not. It is not a nutrition database: it says
/// how much a serving weighs, never what is in it. And it is not a route to
/// calories — grams of *food* multiplied by a per-serving figure is still a
/// serving count, and nothing downstream converts servings into energy.
///
/// Grams are absolute. An ingredient's `grams` is everything of it on the plate,
/// so nothing multiplies this by a dish's count or size: measured on 220 weighed
/// dishes, applying the dish multiplier on top made the estimate worse on every
/// figure that matters — 33% median error against 26%, and 62 dishes wrong by
/// more than double against 39.
public enum ServingWeight {
    /// Grams of food in one serving, by food group. Overridable from
    /// `shaman-config.json`, like every other number that is a judgement rather
    /// than a fact.
    ///
    /// Calibrated to published serving definitions where available —
    /// 100 g of meat or fish, 200 ml of dairy, one egg — and to ordinary
    /// helpings where it does not.
    public static let defaultGrams: [String: Double] = [
        FoodGroup.fish.rawValue: 100,
        FoodGroup.whiteMeat.rawValue: 100,
        FoodGroup.redMeat.rawValue: 100,
        FoodGroup.processedMeat.rawValue: 50,
        FoodGroup.egg.rawValue: 50,
        FoodGroup.dairy.rawValue: 200,
        FoodGroup.legumes.rawValue: 150,
        FoodGroup.nuts.rawValue: 30,
        FoodGroup.wholeGrains.rawValue: 150,
        FoodGroup.refinedGrains.rawValue: 150,
        FoodGroup.vegetables.rawValue: 100,
        FoodGroup.fruit.rawValue: 120,
        FoodGroup.plantFats.rawValue: 30,
        FoodGroup.pastry.rawValue: 60,
        FoodGroup.sweets.rawValue: 30,
        FoodGroup.cookedTomatoSauce.rawValue: 50,
        FoodGroup.butter.rawValue: 15,
        FoodGroup.oliveOil.rawValue: 10,
        FoodGroup.vegetableOil.rawValue: 10,
        FoodGroup.sugaryDrinks.rawValue: 330,
        FoodGroup.coffee.rawValue: 200,
        FoodGroup.tea.rawValue: 200,
        FoodGroup.juice.rawValue: 200,
        FoodGroup.plantMilk.rawValue: 200,
        FoodGroup.smoothie.rawValue: 250,
        // A beer, because a beer is what people photograph. This is the weakest
        // row in the table and the only one that is wrong by construction: an
        // alcoholic drink is defined by its ethanol, not
        // its volume. At 330 a glass of wine reads as a third of a drink and a
        // measure of spirits as almost none. Weighing drinks is the case where
        // grams and servings genuinely disagree, and if the alcohol item ever
        // matters this needs a per-drink answer rather than a per-gram one.
        FoodGroup.alcohol.rawValue: 330,
        FoodGroup.other.rawValue: 100
    ]

    /// Servings from a weight. A group with no entry falls back to 100 g rather
    /// than to zero: a new food group that nobody has weighed yet should count
    /// approximately, not disappear.
    public static func servings(
        fromGrams grams: Double,
        of group: FoodGroup,
        table: [String: Double] = defaultGrams
    ) -> Double {
        let perServing = group.value(in: table) ?? 100
        guard perServing > 0 else { return 0 }
        return grams / perServing
    }
}
