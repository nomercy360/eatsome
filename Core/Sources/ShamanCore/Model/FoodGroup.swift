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
    case wine
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
        case .wine: "Wine"
        case .sofrito: "Sofrito"
        case .other: "Other"
        }
    }

    /// Groups the model confuses often enough that they belong next to each
    /// other in the one-tap correction sheet. Fish read as white meat and
    /// invisible olive oil are the two systematic failures.
    public var commonlyConfusedWith: [FoodGroup] {
        switch self {
        case .fish, .whiteMeat: [.fish, .whiteMeat, .redMeat]
        case .redMeat, .processedMeat: [.redMeat, .processedMeat, .whiteMeat]
        case .wholeGrains, .refinedGrains: [.wholeGrains, .refinedGrains, .legumes]
        case .sweets, .pastry: [.sweets, .pastry]
        case .oliveOil, .butter: [.oliveOil, .butter]
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
}

extension FoodGroup {
    /// Olive oil is scored in tablespoons by MEDAS (item 2 wants >= 4 tbsp/day),
    /// so one "serving" of oil is defined as 2 tbsp and the criterion asks for 2.
    /// Every other group is 1 serving == 1 serving.
    public var tablespoonsPerServing: Double? { self == .oliveOil ? 2.0 : nil }
}
