import Foundation

/// What a day is aiming at, in the five figures `Nutrients` carries.
///
/// Two of these are floors, two are ranges and one is a ceiling, and the type
/// says which because a screen that treats them alike gets salt exactly
/// backwards. `protein` is a floor — reaching it is the point. `kcal`,
/// `carbohydrate` and `fat` are ranges to sit inside. `salt` is a ceiling, and
/// the only figure here where the good direction is down.
///
/// Everything is derived from body weight and intent, which is all the app has:
/// weight arrives from HealthKit and intent is a three-way switch in Settings.
/// Nothing here asks for height, age or sex, so nothing here is Mifflin-St Jeor
/// or Harris-Benedict. Those are better formulas fed data this app does not
/// hold, and asking for a birth date to sharpen a number nobody should be
/// hitting exactly is a bad trade.
public struct DailyTargets: Sendable, Equatable {
    /// Grams. A floor.
    public var protein: Double
    /// Kilocalories. A range, centred here.
    public var kcal: Double
    /// Grams. Derived as the balance of energy left after protein and fat.
    public var carbohydrate: Double
    /// Grams.
    public var fat: Double
    /// Grams of salt equivalent. A ceiling.
    public var salt: Double

    public init(protein: Double, kcal: Double, carbohydrate: Double, fat: Double, salt: Double) {
        self.protein = protein
        self.kcal = kcal
        self.carbohydrate = carbohydrate
        self.fat = fat
        self.salt = salt
    }

    /// Kilocalories per kilogram of body weight per day, by intent.
    ///
    /// Deliberately coarse, and coarser than the protein figure beside it. A
    /// resting expenditure predicted from weight alone carries roughly 15% error
    /// before activity is guessed at, so this is a starting point to be adjusted
    /// against the scale over a fortnight rather than a number to eat to. It is
    /// shown as a range for that reason.
    public static func kilocaloriesPerKilogram(_ intent: Protein.Intent) -> Double {
        switch intent {
        case .maintain: 30
        case .active: 35
        case .building: 40
        }
    }

    /// The share of energy from fat.
    ///
    /// 35%, which is high against the 20–30% most guidelines print and correct
    /// for the diet this app scores. PREDIMED's intervention arms ran 39–42% of
    /// energy from fat, nearly all of it olive oil and nuts, and beat the
    /// low-fat control. A 25% fat target inside a Mediterranean-diet tracker
    /// would mark the olive oil that earns MEDAS points as an overshoot.
    public static let fatShareOfEnergy = 0.35

    /// Grams of salt a day, as a ceiling.
    ///
    /// The WHO recommendation, and an absolute figure rather than a
    /// weight-scaled one because the evidence behind it is about blood pressure
    /// rather than body size.
    ///
    /// Nothing currently shows this next to a derived figure, and that is on
    /// purpose. `Nutrients.saltGrams` is a floor — composition tables publish
    /// unsalted preparations, and it read 82% under a canteen meal that printed
    /// its salt — so a progress bar against 5 g would report every restaurant
    /// lunch as comfortably clear. The ceiling is kept because it is the right
    /// number the day a salt figure exists that can be honestly compared to it,
    /// which means either a panel that printed one or a way to account for what
    /// cooking adds.
    public static let saltCeilingGrams = 5.0

    public static func forBody(weightKilograms: Double, intent: Protein.Intent) -> DailyTargets {
        let protein = Protein.dailyTarget(weightKilograms: weightKilograms, intent: intent)
        let kcal = (weightKilograms * kilocaloriesPerKilogram(intent)).rounded()
        let fat = (kcal * fatShareOfEnergy / 9).rounded()
        // Carbohydrate is the balance, which is both the easiest arithmetic and
        // the honest description: protein is set by body weight, fat by the diet
        // being tracked, and what is left over is carbohydrate. Floored at zero
        // so an unusual weight and intent cannot produce a negative target.
        let carbohydrate = max(0, (kcal - protein * 4 - fat * 9) / 4).rounded()
        return DailyTargets(
            protein: protein,
            kcal: kcal,
            carbohydrate: carbohydrate,
            fat: fat,
            salt: saltCeilingGrams
        )
    }

    /// How wide the energy range around `kcal` is, either side, as a fraction.
    ///
    /// A single number invites eating to it, which is the behaviour this app
    /// spent three years declining to encourage. The band is the honest width of
    /// the estimate and roughly the day-to-day noise in a weight-derived figure.
    public static let energyBand = 0.10

    public var kcalRange: ClosedRange<Double> {
        (kcal * (1 - Self.energyBand)).rounded()...(kcal * (1 + Self.energyBand)).rounded()
    }
}
