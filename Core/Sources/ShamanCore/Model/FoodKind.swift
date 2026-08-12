import Foundation

/// A coarse, nutrition-oriented description used to constrain food lookup.
///
/// This is deliberately not a diet score and not a nutrient row. A kind narrows
/// the search space for a named food; `FoodReference` identifies the actual
/// composition record. Preparation and composition are separate facets so the
/// taxonomy does not need cases such as "fried chicken" or "whole-grain bread".
public enum FoodKind: String, Codable, CaseIterable, Sendable, Hashable {
    case rice
    case pastaNoodles = "pasta_noodles"
    case breadFlatbread = "bread_flatbread"
    case cerealPorridge = "cereal_porridge"
    case potato
    case otherStarchyVegetable = "other_starchy_vegetable"

    case vegetable
    case mushroomSeaweed = "mushroom_seaweed"
    case fruit
    case avocadoOlive = "avocado_olive"
    case legume
    case soyProduct = "soy_product"
    case nutsSeeds = "nuts_seeds"

    case beef
    case pork
    case lambGame = "lamb_game"
    case poultry
    case processedMeat = "processed_meat"
    case organMeat = "organ_meat"
    case fish
    case shellfish
    case egg

    case milk
    case yogurt
    case cheese
    case cream
    case plantMilk = "plant_milk"

    case oil
    case butterMargarine = "butter_margarine"
    case mayonnaiseDressing = "mayonnaise_dressing"
    case sauceCondiment = "sauce_condiment"
    case soupBroth = "soup_broth"

    case sugarHoneySyrup = "sugar_honey_syrup"
    case chocolateCandy = "chocolate_candy"
    case cakeCookie = "cake_cookie"
    case pastry
    case frozenDessert = "frozen_dessert"
    case savorySnack = "savory_snack"
    case nutritionBar = "nutrition_bar"

    case water
    case coffee
    case tea
    case juice
    case smoothie
    case softSportsEnergyDrink = "soft_sports_energy_drink"
    case beer
    case wine
    case spiritCocktail = "spirit_cocktail"

    case supplement
    case mealReplacement = "meal_replacement"
    case unknown

    public var displayName: String {
        switch self {
        case .rice: "Rice"
        case .pastaNoodles: "Pasta & noodles"
        case .breadFlatbread: "Bread & flatbread"
        case .cerealPorridge: "Cereal & porridge"
        case .potato: "Potato"
        case .otherStarchyVegetable: "Other starchy vegetable"
        case .vegetable: "Vegetable"
        case .mushroomSeaweed: "Mushroom & seaweed"
        case .fruit: "Fruit"
        case .avocadoOlive: "Avocado & olives"
        case .legume: "Beans, peas & lentils"
        case .soyProduct: "Soy product"
        case .nutsSeeds: "Nuts & seeds"
        case .beef: "Beef"
        case .pork: "Pork"
        case .lambGame: "Lamb & game"
        case .poultry: "Poultry"
        case .processedMeat: "Processed meat"
        case .organMeat: "Organ meat"
        case .fish: "Fish"
        case .shellfish: "Shellfish"
        case .egg: "Egg"
        case .milk: "Milk"
        case .yogurt: "Yogurt"
        case .cheese: "Cheese"
        case .cream: "Cream"
        case .plantMilk: "Plant milk"
        case .oil: "Cooking oil"
        case .butterMargarine: "Butter & margarine"
        case .mayonnaiseDressing: "Mayonnaise & dressing"
        case .sauceCondiment: "Sauce & condiment"
        case .soupBroth: "Soup & broth"
        case .sugarHoneySyrup: "Sugar, honey & syrup"
        case .chocolateCandy: "Chocolate & candy"
        case .cakeCookie: "Cake & cookies"
        case .pastry: "Pastry"
        case .frozenDessert: "Frozen dessert"
        case .savorySnack: "Savory snack"
        case .nutritionBar: "Nutrition bar"
        case .water: "Water"
        case .coffee: "Coffee"
        case .tea: "Tea"
        case .juice: "Juice"
        case .smoothie: "Smoothie"
        case .softSportsEnergyDrink: "Soft, sports & energy drink"
        case .beer: "Beer"
        case .wine: "Wine"
        case .spiritCocktail: "Spirits & cocktails"
        case .supplement: "Supplement"
        case .mealReplacement: "Meal replacement"
        case .unknown: "Needs identification"
        }
    }

    public var plainName: String { displayName }
    public var shortName: String { displayName }
    public var sentenceName: String { displayName.lowercased() }

    /// Likely corrections shown before the full taxonomy.
    public var commonlyConfusedWith: [FoodKind] {
        switch self {
        case .beef, .pork, .lambGame, .poultry:
            [.beef, .pork, .poultry, .lambGame]
        case .fish, .shellfish: [.fish, .shellfish]
        case .milk, .plantMilk: [.milk, .plantMilk]
        case .cream, .butterMargarine:
            [.cream, .mayonnaiseDressing, .butterMargarine]
        case .rice, .pastaNoodles, .breadFlatbread, .cerealPorridge:
            [.rice, .pastaNoodles, .breadFlatbread, .cerealPorridge]
        case .sauceCondiment, .mayonnaiseDressing, .soupBroth:
            [.sauceCondiment, .mayonnaiseDressing, .soupBroth]
        default: []
        }
    }

    /// Previous development builds stored one diet-oriented `group`. Keeping
    /// this mapping on decode lets their append-only logs open while every new
    /// write uses `kind`.
    /// TAXONOMY_BRIDGE_REMOVE_AFTER_V20_AUDIT: remove after D1 migration and a
    /// clean tester reinstall/resync have both been verified.
    public static func legacy(_ raw: String) -> FoodKind? {
        switch raw {
        case "olive_oil", "vegetable_oil": .oil
        case "vegetables": .vegetable
        case "fruit": .fruit
        case "legumes": .legume
        case "fish": .fish
        case "nuts": .nutsSeeds
        case "plant_fats", "healthy_fats": .avocadoOlive
        case "whole_grains", "refined_grains", "whole_grain", "refined_grain": .breadFlatbread
        case "white_meat": .poultry
        case "red_meat": .beef
        case "processed_meat": .processedMeat
        case "dairy": .milk
        case "egg": .egg
        case "sweets": .chocolateCandy
        case "pastry": .pastry
        case "sugary_drinks": .softSportsEnergyDrink
        case "coffee": .coffee
        case "tea": .tea
        case "juice": .juice
        case "plant_milk": .plantMilk
        case "smoothie": .smoothie
        case "butter", "butter_margarine_cream": .butterMargarine
        case "alcohol": .beer
        case "cooked_tomato_sauce", "sofrito", "sauce": .sauceCondiment
        case "potatoes": .potato
        case "other": .unknown
        default: nil
        }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FoodKind(rawValue: raw) ?? Self.legacy(raw) ?? .unknown
    }
}

public enum PreparationMethod: String, Codable, CaseIterable, Sendable, Hashable {
    case raw, boiled, steamed, baked, roasted, grilled
    case panFried = "pan_fried"
    case deepFried = "deep_fried"
    case smoked, cured, fermented, dried
}

public enum CompositionHint: String, Codable, CaseIterable, Sendable, Hashable {
    case wholeGrain = "whole_grain"
    case refinedGrain = "refined_grain"
    case breaded, sweetened, unsweetened
    case tomatoBased = "tomato_based"
    case soyBased = "soy_based"
    case dairyBased = "dairy_based"
    case oilBased = "oil_based"
    case meatBased = "meat_based"
    case creamy
}

public struct FoodAlternative: Codable, Sendable, Hashable {
    public var label: String
    public var kind: FoodKind

    public init(label: String, kind: FoodKind) {
        self.label = label
        self.kind = kind
    }
}

public enum FoodDatabase: String, Codable, Sendable, Hashable {
    case usdaFDC = "usda_fdc"
    case mext
    case label
}

public struct FoodReference: Codable, Sendable, Hashable {
    public var database: FoodDatabase
    public var id: String
    public var version: String
    public var canonicalName: String

    public init(database: FoodDatabase, id: String, version: String, canonicalName: String) {
        self.database = database
        self.id = id
        self.version = version
        self.canonicalName = canonicalName
    }
}

public enum NutrientResolutionStatus: String, Codable, Sendable, Hashable {
    case label, exact
    case userConfirmed = "user_confirmed"
    case classEstimate = "class_estimate"
    case unresolved
}

public struct NutrientResolution: Codable, Sendable, Hashable {
    public var status: NutrientResolutionStatus
    public var foodRef: FoodReference?
    public var reason: String?

    public init(
        status: NutrientResolutionStatus,
        foodRef: FoodReference? = nil,
        reason: String? = nil
    ) {
        self.status = status
        self.foodRef = foodRef
        self.reason = reason
    }

    public static func unresolved(_ reason: String) -> NutrientResolution {
        NutrientResolution(status: .unresolved, reason: reason)
    }
}
