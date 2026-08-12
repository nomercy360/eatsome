/// What one legacy display serving of each broad food kind weighs.
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
    /// Grams of food in one serving, by food kind. Overridable from
    /// `shaman-config.json`, like every other number that is a judgement rather
    /// than a fact.
    ///
    /// Calibrated to published serving definitions where available —
    /// 100 g of meat or fish, 200 ml of dairy, one egg — and to ordinary
    /// helpings where it does not.
    public static let defaultGrams: [String: Double] = Dictionary(
        uniqueKeysWithValues: FoodKind.allCases.map { kind in
            let grams: Double = switch kind {
            case .oil: 10
            case .butterMargarine: 15
            case .mayonnaiseDressing, .sauceCondiment: 30
            case .nutsSeeds, .chocolateCandy, .sugarHoneySyrup: 30
            case .egg: 50
            case .processedMeat, .cheese, .pastry, .cakeCookie, .savorySnack, .nutritionBar: 60
            case .beef, .pork, .lambGame, .poultry, .organMeat, .fish, .shellfish: 100
            case .vegetable, .mushroomSeaweed, .potato, .otherStarchyVegetable: 100
            case .fruit, .avocadoOlive: 120
            case .rice, .pastaNoodles, .breadFlatbread, .cerealPorridge, .legume, .soyProduct: 150
            case .milk, .yogurt, .cream, .plantMilk, .coffee, .tea, .juice, .soupBroth: 200
            case .smoothie, .mealReplacement: 250
            case .softSportsEnergyDrink, .beer, .water: 330
            case .wine: 150
            case .spiritCocktail: 45
            case .frozenDessert: 100
            case .supplement: 10
            case .unknown: 100
            }
            return (kind.rawValue, grams)
        }
    )

    /// Servings from a weight. A group with no entry falls back to 100 g rather
    /// than to zero: a new food kind that nobody has weighed yet should count
    /// approximately, not disappear.
    public static func servings(
        fromGrams grams: Double,
        of group: FoodKind,
        table: [String: Double] = defaultGrams
    ) -> Double {
        let perServing = table[group.rawValue] ?? 100
        guard perServing > 0 else { return 0 }
        return grams / perServing
    }
}
