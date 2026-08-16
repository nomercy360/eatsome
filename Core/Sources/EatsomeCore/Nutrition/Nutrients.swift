import Foundation

/// Seven figures for a quantity of food: the four macronutrient columns every
/// composition table publishes, plus sodium, alcohol, and caffeine.
///
/// This is a *measurement carrier*, not an estimate. Every value in one of these
/// arrived by multiplying a weight the model read off a photograph by the
/// composition it named for that food, or by transcribing a printed panel.
///
/// Units are not uniform and cannot be, because the sources are not: grams for
/// the macros and alcohol, kilocalories for energy, milligrams for sodium and
/// caffeine. Naming them is the defence — `sodium` is the only field whose unit
/// is not its name, and `saltGrams` exists so the conversion is written once.
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
    /// Grams of ethanol, and the column the previous schema did not have.
    ///
    /// Its absence was not neutral. Ethanol is 7 kcal/g and its energy was
    /// already inside `kcal`, so `protein × 4 + carbohydrate × 4 + fat × 9`
    /// could never reconcile with the energy of anything alcoholic — the
    /// Atwater self-check, which is the loud failure this whole design relies
    /// on, was quietly failing on every beer and reporting it as a bad
    /// composition. A pint of lager is roughly 180 kcal of which about 160 is
    /// ethanol; the check would see 89% of the energy unaccounted for and have
    /// no way to say why.
    ///
    /// Adding it is only cheap once. A field the model was never asked for
    /// cannot be backfilled, because nobody is going back to say whether a
    /// drink logged last Tuesday was a beer.
    public var alcohol: Double
    /// Milligrams of caffeine.
    ///
    /// Composition, not a label transcription. It used to live on
    /// `NutritionPanel`, which meant a food only had caffeine if a printed panel
    /// was in the photograph — so a filter coffee, the single most common
    /// caffeinated thing anybody logs, had none. Composition tables publish
    /// caffeine per 100 g exactly as they publish sodium per 100 g, and putting
    /// it here means it scales with weight and sums across a day by the same
    /// arithmetic as everything else, instead of by a special case.
    public var caffeine: Double

    public init(
        protein: Double = 0,
        fat: Double = 0,
        carbohydrate: Double = 0,
        kcal: Double = 0,
        sodium: Double = 0,
        alcohol: Double = 0,
        caffeine: Double = 0
    ) {
        self.protein = protein
        self.fat = fat
        self.carbohydrate = carbohydrate
        self.kcal = kcal
        self.sodium = sodium
        self.alcohol = alcohol
        self.caffeine = caffeine
    }

    public static let zero = Nutrients()

    /// Explicit, and spelling the one ambiguous unit out on the wire and on
    /// disk. `sodium` is milligrams while every label prints grams of salt, and
    /// a field named for neither is how a factor of a thousand gets lost.
    private enum CodingKeys: String, CodingKey {
        case protein, fat, carbohydrate, kcal, alcohol
        case sodium = "sodium_mg"
        case caffeine = "caffeine_mg"
    }

    /// Grams of salt equivalent, which is what a person recognises and what
    /// every label outside the United States prints.
    ///
    /// The factor is the molar mass ratio of sodium chloride to sodium,
    /// 58.44 / 22.99. It is arithmetic on a definition rather than a second
    /// measurement, which is why it is derived here instead of being stored as
    /// another column: a type that carried both could disagree with itself.
    public static let saltPerSodium = 58.44 / 22.99

    /// Grams of salt equivalent.
    ///
    /// Not a floor. Composition arrives with the food and is priced as eaten,
    /// seasoning included — asked about guacamole the model answers 430 mg
    /// where an unsalted avocado row said 8. A screen should still consult
    /// `NutrientProvenance` before dressing this as a measurement.
    public var saltGrams: Double { sodium * Self.saltPerSodium / 1000 }

    /// A weight of a food whose composition is known per 100 g.
    public func scaled(by factor: Double) -> Nutrients {
        Nutrients(
            protein: protein * factor,
            fat: fat * factor,
            carbohydrate: carbohydrate * factor,
            kcal: kcal * factor,
            sodium: sodium * factor,
            alcohol: alcohol * factor,
            caffeine: caffeine * factor
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
            sodium: lhs.sodium + rhs.sodium,
            alcohol: lhs.alcohol + rhs.alcohol,
            caffeine: lhs.caffeine + rhs.caffeine
        )
    }

    public static func += (lhs: inout Nutrients, rhs: Nutrients) { lhs = lhs + rhs }
}

// MARK: - The self-check

extension Nutrients {
    /// Kilocalories per gram, by macronutrient. The Atwater general factors,
    /// plus ethanol's 7.
    public static let energyPerGram = (protein: 4.0, carbohydrate: 4.0, fat: 9.0, alcohol: 7.0)

    /// What the macronutrients say the energy should be.
    public var atwaterEnergy: Double {
        protein * Self.energyPerGram.protein
            + carbohydrate * Self.energyPerGram.carbohydrate
            + fat * Self.energyPerGram.fat
            + alcohol * Self.energyPerGram.alcohol
    }

    /// How far the stated energy is from what its own macronutrients imply, as
    /// a fraction of the stated energy. Nil when there is no energy to check
    /// against — zero is not a disagreement, it is an absence.
    ///
    /// This is the loud failure. With composition stored rather than looked up
    /// there is no such thing as a weight that resolved to nothing, so a bad
    /// answer would otherwise be silent; this is what makes it visible. It is
    /// stated in the recognition prompt, checked in the Zod contract, and
    /// checked here so a meal that arrives by any other path is checked too.
    public var atwaterDelta: Double? {
        guard kcal > 0 else { return nil }
        return abs(atwaterEnergy - kcal) / kcal
    }

    /// Ten percent. Wide enough for rounding in a published panel and for the
    /// genuine spread in Atwater factors between foods; narrow enough that a
    /// missing column shows up. It read 2.3% against an official Subway panel.
    public static let atwaterTolerance = 0.1

    /// True when the figures disagree with themselves by more than the
    /// tolerance. False when there is nothing to check.
    public var failsAtwater: Bool {
        guard let delta = atwaterDelta else { return false }
        return delta > Self.atwaterTolerance
    }
}
