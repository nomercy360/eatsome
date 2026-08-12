import Foundation

/// Five figures for a quantity of food: the four macronutrient columns every
/// composition table publishes, plus sodium.
///
/// This is a *measurement carrier*, not an estimate. Every value in one of these
/// arrived by multiplying a weight the model read off a photograph by a figure a
/// food composition table published for a named food, or by transcribing a
/// printed panel. Nothing in this type is a model's opinion about energy, and
/// that is the entire basis on which the app is allowed to total them.
///
/// Units are not uniform and cannot be, because the sources are not: grams for
/// the three macros, kilocalories for energy, milligrams for sodium. Naming them
/// is the defence — `sodium` is the only field whose unit is not its name, and
/// `saltGrams` exists so the conversion is written once.
public struct Nutrients: Codable, Sendable, Hashable {
    /// Grams.
    public var protein: Double
    /// Grams.
    public var fat: Double
    /// Grams.
    public var carbohydrate: Double
    /// Kilocalories.
    public var kcal: Double
    /// Milligrams. Tables publish sodium; labels print salt. See `saltGrams`.
    public var sodium: Double

    public init(
        protein: Double = 0,
        fat: Double = 0,
        carbohydrate: Double = 0,
        kcal: Double = 0,
        sodium: Double = 0
    ) {
        self.protein = protein
        self.fat = fat
        self.carbohydrate = carbohydrate
        self.kcal = kcal
        self.sodium = sodium
    }

    public static let zero = Nutrients()

    /// Explicit, and spelling the one ambiguous unit out on the wire and on
    /// disk. `sodium` is milligrams while every label prints grams of salt, and
    /// a field named for neither is how a factor of a thousand gets lost.
    private enum CodingKeys: String, CodingKey {
        case protein, fat, carbohydrate, kcal
        case sodium = "sodium_mg"
    }

    /// Grams of salt equivalent, which is what a person recognises and what
    /// every label outside the United States prints.
    ///
    /// The factor is the molar mass ratio of sodium chloride to sodium,
    /// 58.44 / 22.99. It is arithmetic on a definition rather than a second
    /// measurement, which is why it is derived here instead of being stored as a
    /// sixth column: a table that carried both could disagree with itself.
    public static let saltPerSodium = 58.44 / 22.99

    /// Grams of salt equivalent.
    ///
    /// Until v21 this was a documented floor rather than an estimate, because
    /// the figure came from a composition table and composition tables publish
    /// plain preparations: cooked white rice is 1 mg of sodium per 100 g, while
    /// the salt in cooked food is added in sauces and seasoning that carry no
    /// weight on the plate. Measured against a canteen bibimbap that printed
    /// 4 g, the derived figure was 0.7 g — 82% low, and structurally so.
    ///
    /// Composition now comes with the food, priced as eaten, so the bias is
    /// gone with the table that caused it: asked for guacamole, the model
    /// answers 430 mg where the unsalted avocado row said 8. A screen should
    /// still consult `NutrientProvenance` before dressing this as a
    /// measurement, but it is no longer a lower bound by construction.
    public var saltGrams: Double { sodium * Self.saltPerSodium / 1000 }

    /// A weight of a food whose composition is known per 100 g.
    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(
            protein: protein * factor,
            fat: fat * factor,
            carbohydrate: carbohydrate * factor,
            kcal: kcal * factor,
            sodium: sodium * factor
        )
    }

    /// What `grams` of a food with this composition per 100 g contributes.
    public func forGrams(_ grams: Double) -> Nutrients { scaled(by: grams / 100) }

    public static func + (lhs: Nutrients, rhs: Nutrients) -> Nutrients {
        Nutrients(
            protein: lhs.protein + rhs.protein,
            fat: lhs.fat + rhs.fat,
            carbohydrate: lhs.carbohydrate + rhs.carbohydrate,
            kcal: lhs.kcal + rhs.kcal,
            sodium: lhs.sodium + rhs.sodium
        )
    }

    public static func += (lhs: inout Nutrients, rhs: Nutrients) { lhs = lhs + rhs }
}
