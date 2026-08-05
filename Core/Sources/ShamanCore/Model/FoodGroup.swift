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
    /// MEDAS has no item for them, so they count nowhere — which is the honest
    /// answer, and better than counting in the wrong place.
    case healthyFats = "healthy_fats"
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
    case butter
    case alcohol
    case sofrito
    case other

    public var displayName: String {
        switch self {
        case .oliveOil: "Olive oil"
        case .vegetables: "Vegetables"
        case .fruit: "Fruit"
        case .legumes: "Legumes"
        case .fish: "Fish & seafood"
        case .nuts: "Nuts"
        case .healthyFats: "Avocado, olives & seeds"
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
        case .butter: "Butter / margarine / cream"
        case .alcohol: "Alcohol"
        case .sofrito: "Sofrito"
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
        case .healthyFats: "Avocado, olives & seeds"
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
        case .butter: "Butter & cream"
        case .alcohol: "Alcohol"
        case .sofrito: "Tomato & onion base"
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
        case .healthyFats: "Avocado & olives"
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
        case .butter: "Butter"
        case .alcohol: "Alcohol"
        case .sofrito: "Tomato base"
        case .other: "Something else"
        }
    }

    /// Lowercased for mid-sentence use, where a capital would read as a proper
    /// noun: "Looks like chicken and olive oil."
    public var sentenceName: String {
        shortName.lowercased()
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
        case .oliveOil, .butter: [.oliveOil, .butter, .healthyFats]
        case .fruit, .vegetables, .healthyFats: [.fruit, .vegetables, .healthyFats]
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
