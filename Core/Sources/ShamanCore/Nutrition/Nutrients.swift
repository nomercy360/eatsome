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
public struct Nutrients: Codable, Sendable, Equatable {
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

    /// Grams of salt equivalent, which is what a person recognises and what
    /// every label outside the United States prints.
    ///
    /// The factor is the molar mass ratio of sodium chloride to sodium,
    /// 58.44 / 22.99. It is arithmetic on a definition rather than a second
    /// measurement, which is why it is derived here instead of being stored as a
    /// sixth column: a table that carried both could disagree with itself.
    public static let saltPerSodium = 58.44 / 22.99

    /// Grams of salt equivalent, and a FLOOR rather than an estimate.
    ///
    /// This is the one figure of the five where the derivation is known to be
    /// biased and known which way. Composition tables publish plain
    /// preparations — cooked white rice is 1 mg of sodium per 100 g — while the
    /// salt in cooked food is mostly added during cooking, in sauces and
    /// seasoning that carry no weight on the plate and appear in no ingredient
    /// list. Measured against a canteen bibimbap that printed 4 g, this derived
    /// 0.7 g: 82% low, and structurally so. See `Backend/eval/nutrients.ts`.
    ///
    /// So it is the salt *in the food*, and real food contains at least this
    /// much. Nothing may present it as a measurement of intake or compare it to
    /// `DailyTargets.salt` as though a small number meant a good day — a salt
    /// figure that reads "well under" on a 4 g lunch is exactly the kind of
    /// confident, complete-looking, wrong total this app declines to show.
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

/// A `Nutrients` total, and how much of the food behind it actually answered.
///
/// The second half is not decoration. A daily energy figure built from the two
/// thirds of a plate that resolved is not a small error, it is a different
/// number wearing the same label — and unlike a missing figure, it is invisible.
/// Protein survived without this because a miss fell through to
/// `Protein.defaultGramsPerServing`, which covers every food group; energy has no
/// such hand-calibrated table, so `FoodNutrientTable.groups` stands behind it and
/// `unresolvedGrams` counts the weight that even that could not answer for.
///
/// In practice the only food that lands here is `FoodGroup.other`, the bucket for
/// something the model did not recognise. That is deliberate: `other` has no
/// representative row precisely because a figure for unrecognised food would be
/// invented rather than estimated, and the honest response is to report the
/// total as short by this much and let the person name the food.
public struct NutrientTotal: Sendable, Equatable {
    public var nutrients: Nutrients
    /// Grams of food that produced no figure at all.
    public var unresolvedGrams: Double
    /// Grams of food that did produce one.
    public var resolvedGrams: Double
    /// Whether any of the sodium above was derived from a composition table
    /// rather than read off a printed panel.
    ///
    /// The distinction is the difference between a fact and a lower bound, and
    /// it has to be carried rather than assumed. A can of Monster prints
    /// 食塩相当量 0.1 g per 100 ml: scaled to the can that is 0.36 g and it is
    /// exactly 0.36 g, so showing it as "≥ 0.4" would understate a figure the
    /// label already settled. A bowl of ramen has no label, derives 0.7 g from
    /// the noodles and the pork, and genuinely contains several times that.
    ///
    /// A plate mixing the two is a floor, because the unlabelled half is.
    public var saltIsFloor: Bool

    public init(
        nutrients: Nutrients = .zero,
        unresolvedGrams: Double = 0,
        resolvedGrams: Double = 0,
        saltIsFloor: Bool = false
    ) {
        self.nutrients = nutrients
        self.unresolvedGrams = unresolvedGrams
        self.resolvedGrams = resolvedGrams
        self.saltIsFloor = saltIsFloor
    }

    public static let zero = NutrientTotal()

    /// Whether every gram of food on the plate produced a figure.
    public var isComplete: Bool { unresolvedGrams == 0 }

    /// The share of the weight that answered, 0...1. One when there was no food
    /// at all, because a total of nothing is not an incomplete total.
    public var coverage: Double {
        let weighed = resolvedGrams + unresolvedGrams
        return weighed > 0 ? resolvedGrams / weighed : 1
    }

    public func scaled(by factor: Double) -> NutrientTotal {
        NutrientTotal(
            nutrients: nutrients.scaled(by: factor),
            unresolvedGrams: unresolvedGrams * factor,
            resolvedGrams: resolvedGrams * factor,
            saltIsFloor: saltIsFloor
        )
    }

    public static func + (lhs: NutrientTotal, rhs: NutrientTotal) -> NutrientTotal {
        NutrientTotal(
            nutrients: lhs.nutrients + rhs.nutrients,
            unresolvedGrams: lhs.unresolvedGrams + rhs.unresolvedGrams,
            resolvedGrams: lhs.resolvedGrams + rhs.resolvedGrams,
            // One unlabelled dish makes the whole plate a floor. Salt is the
            // figure where a confident understatement does the most damage, so
            // the pessimistic side is the right side to round to.
            saltIsFloor: lhs.saltIsFloor || rhs.saltIsFloor
        )
    }

    public static func += (lhs: inout NutrientTotal, rhs: NutrientTotal) { lhs = lhs + rhs }
}
