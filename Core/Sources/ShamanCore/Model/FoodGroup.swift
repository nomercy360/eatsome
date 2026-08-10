import Foundation

/// The unit of measurement for this app. Not calories.
///
/// A vision model asked "how many grams of rice is this" produces a number with
/// 30-50% error that still *looks* like data. Asked "is there a starch here, and
/// is the portion small, medium, or large", it is reliable. The Mediterranean
/// diet is scored on food-group frequency (PREDIMED/MEDAS), so the metric we
/// actually want is the one the model can actually deliver.
public enum FoodGroup: String, Codable, CaseIterable, Sendable, Hashable {
    case oliveOil = "olive_oil"
    case vegetables
    case fruit
    case legumes
    case fish
    case nuts
    /// Avocado, olives, seeds, tahini. Separate from fruit and vegetables
    /// because they are a fat source, and scoring an avocado as fruit both
    /// credits a fruit serving you did not eat and hides the fat you did.
    ///
    /// Called `healthy_fats` until the taxonomy audit: that was a verdict rather
    /// than a food, and a verdict is a thing only one diet holds — keto
    /// disagrees with it about cream, and a group name is the wrong place to
    /// have that argument. Same members, no opinion. Legacy lines still decode.
    case plantFats = "plant_fats"
    case wholeGrains = "whole_grains"
    case refinedGrains = "refined_grains"
    case whiteMeat = "white_meat"
    case redMeat = "red_meat"
    case processedMeat = "processed_meat"
    case dairy
    case egg
    case sweets
    case pastry
    case sugaryDrinks = "sugary_drinks"
    /// What a person drinks, split out from `other` because that bucket was
    /// answering for all of it. Filed under `other` a coffee inherited the
    /// bucket's protein estimate, and 2 g of protein in a black coffee is a
    /// number the app invented. MEDAS has no item for any of these, so they
    /// score nowhere — the same honest nothing `healthyFats` gets.
    ///
    /// A latte is a `coffee` ingredient and a `dairy` ingredient in one dish,
    /// not dairy alone: the milk and the caffeine are different facts.
    case coffee
    case tea
    case juice
    case plantMilk = "plant_milk"
    case smoothie
    case butter
    /// Seed and vegetable oils — sunflower, rapeseed, soybean, corn, the
    /// unnamed frying oil behind most takeaway food.
    ///
    /// Added by the taxonomy audit, and it is the one addition: olive oil was
    /// fine as a group, but being the *only* named oil meant every other oil
    /// vanished into nothing at all. A diet that limits seed oils had no
    /// evidence to rule on, and the olive-oil habit question ("is it your main
    /// fat?") had evidence on one side only. One group, and the whole
    /// clean-eating family becomes expressible.
    case vegetableOil = "vegetable_oil"
    case alcohol
    /// The cooked tomato-and-onion base most stews start with.
    ///
    /// Called `sofrito` until the taxonomy audit, where it was the clearest case
    /// of a group that existed only because one screener asks for it — MEDAS
    /// item 14. The food is real and worth recognising in any diet; the Spanish
    /// name for it was the Mediterranean showing through the vocabulary. The
    /// MEDAS preset maps it straight back.
    case cookedTomatoSauce = "cooked_tomato_sauce"
    case other

    public var displayName: String {
        switch self {
        case .oliveOil: "Olive oil"
        case .vegetables: "Vegetables"
        case .fruit: "Fruit"
        case .legumes: "Legumes"
        case .fish: "Fish & seafood"
        case .nuts: "Nuts"
        case .plantFats: "Avocado, olives & seeds"
        case .wholeGrains: "Whole grains"
        case .refinedGrains: "Refined grains"
        case .whiteMeat: "White meat"
        case .redMeat: "Red meat"
        case .processedMeat: "Processed meat"
        case .dairy: "Dairy"
        case .egg: "Egg"
        case .sweets: "Sweets"
        case .pastry: "Commercial pastry"
        case .sugaryDrinks: "Sugary drinks"
        case .coffee: "Coffee"
        case .tea: "Tea"
        case .juice: "Juice"
        case .plantMilk: "Plant milk"
        case .smoothie: "Smoothie"
        case .butter: "Butter / margarine / cream"
        case .vegetableOil: "Vegetable & seed oil"
        case .alcohol: "Alcohol"
        case .cookedTomatoSauce: "Cooked tomato sauce"
        case .other: "Other"
        }
    }

    /// What a person would call this at the table.
    ///
    /// `displayName` is the screener's vocabulary — "Legumes", "Refined grains",
    /// "Commercial pastry" — and it is the right label next to a score, in
    /// diagnostics, and in an eval. It is the wrong label on a chip you tap
    /// while holding a plate. Both exist because the manual picker shows them
    /// together: the plain name on the row, the group it counts as underneath.
    ///
    /// Display only. Raw values are the on-disk format and do not move.
    public var plainName: String {
        switch self {
        case .oliveOil: "Olive oil"
        case .vegetables: "Vegetables"
        case .fruit: "Fruit"
        case .legumes: "Beans & lentils"
        case .fish: "Fish & seafood"
        case .nuts: "Nuts"
        case .plantFats: "Avocado, olives & seeds"
        case .wholeGrains: "Wholegrain bread & pasta"
        case .refinedGrains: "Bread & pasta"
        case .whiteMeat: "Chicken & turkey"
        case .redMeat: "Beef, pork & lamb"
        case .processedMeat: "Ham, bacon & sausage"
        case .dairy: "Yoghurt, milk & cheese"
        case .egg: "Eggs"
        case .sweets: "Sweets & chocolate"
        case .pastry: "Cakes & pastry"
        case .sugaryDrinks: "Fizzy & sweet drinks"
        case .coffee: "Coffee & espresso"
        case .tea: "Tea"
        case .juice: "Fruit juice"
        case .plantMilk: "Oat & soy milk"
        case .smoothie: "Smoothie"
        case .butter: "Butter & cream"
        case .vegetableOil: "Sunflower & seed oil"
        case .alcohol: "Alcohol"
        case .cookedTomatoSauce: "Tomato & onion base"
        case .other: "Something else"
        }
    }

    /// One or two words, for a chip and for the middle of a sentence.
    ///
    /// `plainName` is written for a picker row, where a second line names the
    /// group it counts as and there is room to be unambiguous. A chip has room
    /// for neither: "Yoghurt, milk & cheese" wraps to two lines and pushes the
    /// rest of the row off the card, where "Dairy" does not.
    public var shortName: String {
        switch self {
        case .oliveOil: "Olive oil"
        case .vegetables: "Vegetables"
        case .fruit: "Fruit"
        case .legumes: "Beans"
        case .fish: "Fish"
        case .nuts: "Nuts"
        case .plantFats: "Avocado & olives"
        case .wholeGrains: "Whole grains"
        case .refinedGrains: "Bread & pasta"
        case .whiteMeat: "Chicken"
        case .redMeat: "Red meat"
        case .processedMeat: "Cured meat"
        case .dairy: "Dairy"
        case .egg: "Eggs"
        case .sweets: "Sweets"
        case .pastry: "Pastry"
        case .sugaryDrinks: "Sweet drinks"
        case .coffee: "Coffee"
        case .tea: "Tea"
        case .juice: "Juice"
        case .plantMilk: "Plant milk"
        case .smoothie: "Smoothie"
        case .butter: "Butter"
        case .vegetableOil: "Seed oil"
        case .alcohol: "Alcohol"
        case .cookedTomatoSauce: "Tomato base"
        case .other: "Something else"
        }
    }

    /// Lowercased for mid-sentence use, where a capital would read as a proper
    /// noun: "Looks like chicken and olive oil."
    public var sentenceName: String {
        shortName.lowercased()
    }

    /// What this group used to be called on disk.
    ///
    /// The taxonomy audit renamed two groups, and a rename is normally the one
    /// thing this enum may not do: raw values are the on-disk format, and a
    /// `MealItem` that will not decode is a meal that silently vanishes from the
    /// projection. So the rename happens on the way *out* and the old spelling
    /// still resolves on the way in — `events.jsonl` is untouched, every line
    /// written before today still reads, and nothing has to be rewritten.
    ///
    /// The same aliases apply to the string-keyed tables in
    /// `shaman-config.json`: a config file already cached on a phone keys
    /// `sofrito` and `healthy_fats`, and it must keep working. See `value(in:)`.
    static let legacyNames: [String: FoodGroup] = [
        "sofrito": .cookedTomatoSauce,
        "healthy_fats": .plantFats
    ]

    /// Every spelling this group answers to, current first. The lookup order in
    /// `value(in:)`, and what a table-completeness test has to iterate.
    public var storedNames: [String] {
        [rawValue] + Self.legacyNames.filter { $0.value == self }.keys.sorted()
    }

    /// A group's entry in a table keyed by raw value, current spelling first.
    ///
    /// Every remote-config table — protein per serving, serving weights, olive
    /// weights, the food table's group representatives — is `[String: T]`, and
    /// a rename would otherwise silently drop a row into its default. Silently:
    /// `sofrito` would stop weighing 50 g and start weighing 100 g, and nothing
    /// on any screen would say so.
    public func value<T>(in table: [String: T]) -> T? {
        for name in storedNames {
            if let hit = table[name] { return hit }
        }
        return nil
    }

    /// An unknown value is a group written by a build newer than this one, or
    /// one of the two spellings the audit retired.
    ///
    /// `other` rather than a thrown error, for the reason `MealShare` and
    /// `MealSource` give: a `MealEntry` that will not decode is a meal that
    /// disappears from the score with no error anywhere, and a food filed under
    /// "something else" is visibly wrong in a way a missing meal is not. It also
    /// lands in `NutrientTotal.unresolvedGrams`, which every total has to
    /// surface — so the loss is stated rather than absorbed.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodGroup(rawValue: raw) ?? FoodGroup.legacyNames[raw] ?? .other
    }

    /// Groups the model confuses often enough that they belong next to each
    /// other in the one-tap correction sheet. Fish read as white meat, invisible
    /// olive oil, and avocado filed as produce are the systematic failures.
    public var commonlyConfusedWith: [FoodGroup] {
        switch self {
        case .fish, .whiteMeat: [.fish, .whiteMeat, .redMeat]
        case .redMeat, .processedMeat: [.redMeat, .processedMeat, .whiteMeat]
        case .wholeGrains, .refinedGrains: [.wholeGrains, .refinedGrains, .legumes]
        case .sweets, .pastry: [.sweets, .pastry]
        // Which fat a dish was cooked in is the hardest thing on this list to
        // see, and now that seed oil has a group of its own it is also the
        // question a clean-eating diet turns on — so it sits with the other two.
        case .oliveOil, .butter, .vegetableOil: [.oliveOil, .vegetableOil, .butter]
        case .fruit, .vegetables, .plantFats: [.fruit, .vegetables, .plantFats]
        // A dark drink in a mug is coffee or tea and a photo rarely settles it,
        // and juice, smoothie and a sweetened bottle are the same liquid to a
        // camera. Plant milk pairs with dairy, which is what it is mistaken for.
        case .coffee, .tea: [.coffee, .tea]
        case .juice, .smoothie, .sugaryDrinks: [.juice, .smoothie, .sugaryDrinks]
        case .plantMilk, .dairy: [.plantMilk, .dairy]
        default: []
        }
    }
}

/// Deliberately coarse. Grams would be a lie; this is what a photo supports.
public enum Portion: String, Codable, CaseIterable, Sendable, Hashable {
    case small
    case medium
    case large

    /// MEDAS "servings". One medium portion is one serving.
    public var servings: Double {
        switch self {
        case .small: 0.5
        case .medium: 1.0
        case .large: 2.0
        }
    }

    /// How much, said the way you would say it out loud. "Medium" is a size
    /// chart; "Normal" is the answer to "how much of it was there".
    public var plainName: String {
        switch self {
        case .small: "A little"
        case .medium: "Normal"
        case .large: "A lot"
        }
    }
}

extension FoodGroup {
    /// Olive oil is scored in tablespoons by MEDAS (item 2 wants >= 4 tbsp/day),
    /// so one "serving" of oil is defined as 2 tbsp and the criterion asks for 2.
    /// Every other group is 1 serving == 1 serving.
    public var tablespoonsPerServing: Double? { self == .oliveOil ? 2.0 : nil }
}
