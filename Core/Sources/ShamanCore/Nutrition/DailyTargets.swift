import Foundation

/// A personal daily planning reference derived from a complete
/// `NutritionProfile`.
///
/// Maintenance energy uses the adult 2023 National Academies Dietary Reference
/// Intake equations. Carbohydrate, fat and protein ranges use the adult AMDRs:
/// 45–65%, 20–35% and 10–35% of energy respectively. They are ranges because
/// the science publishes ranges; turning them into a single macro split would
/// add a preference the source does not contain.
public struct DailyTargets: Sendable, Equatable {
    /// Estimated maintenance energy in kilocalories per day.
    public var maintenanceKcal: Double
    /// The planning centre after the selected goal adjustment.
    public var kcal: Double
    /// A goal-specific protein reference in grams. `proteinRange` remains the
    /// population AMDR; this figure is the simpler number shown day to day.
    public var protein: Double
    public var proteinMinimum: Double
    public var proteinRange: ClosedRange<Double>
    public var carbohydrateRange: ClosedRange<Double>
    public var fatRange: ClosedRange<Double>
    /// Grams of salt equivalent. A ceiling.
    public var salt: Double
    /// Signed difference between the goal centre and maintenance energy.
    public var goalAdjustmentKcal: Double

    public init(
        maintenanceKcal: Double,
        kcal: Double,
        protein: Double,
        proteinMinimum: Double,
        proteinRange: ClosedRange<Double>,
        carbohydrateRange: ClosedRange<Double>,
        fatRange: ClosedRange<Double>,
        salt: Double,
        goalAdjustmentKcal: Double
    ) {
        self.maintenanceKcal = maintenanceKcal
        self.kcal = kcal
        self.protein = protein
        self.proteinMinimum = proteinMinimum
        self.proteinRange = proteinRange
        self.carbohydrateRange = carbohydrateRange
        self.fatRange = fatRange
        self.salt = salt
        self.goalAdjustmentKcal = goalAdjustmentKcal
    }

    /// Grams of salt a day, as a ceiling. Kept separate from macro planning:
    /// meal salt totals are often floors because cooking salt is invisible.
    public static let saltCeilingGrams = 5.0

    /// A 500 kcal deficit is the moderate reference used by U.S. weight-loss
    /// guidance. The 20% cap makes it smaller for lower maintenance estimates.
    public static let maximumWeightLossDeficit = 500.0
    public static let maximumWeightLossFraction = 0.20

    /// Evidence does not establish one exact surplus for hypertrophy. The low
    /// end of the published 10–20% range is used so the planning reference is
    /// conservative and visibly separate from maintenance energy.
    public static let muscleGainSurplusFraction = 0.10

    public static func forProfile(_ profile: NutritionProfile) -> DailyTargets? {
        guard profile.isComplete,
              let weight = profile.weightKilograms,
              let sex = profile.referenceSex,
              let goal = profile.goal,
              let maintenance = maintenanceEnergy(for: profile)
        else { return nil }

        let planned: Double
        switch goal {
        case .maintain:
            planned = maintenance
        case .loseWeight:
            // Do not generate an automatic deficit below the adult underweight
            // threshold. The profile remains usable; the displayed reference
            // stays at maintenance and the UI explains why.
            if let bmi = profile.bodyMassIndex, bmi < 18.5 {
                planned = maintenance
            } else {
                let deficit = min(maximumWeightLossDeficit, maintenance * maximumWeightLossFraction)
                let floor = sex == .female ? 1_200.0 : 1_500.0
                planned = max(floor, maintenance - deficit)
            }
        case .gainMuscle:
            planned = maintenance * (1 + muscleGainSurplusFraction)
        }

        let energy = planned.rounded()
        let minimumProtein = (weight * 0.8).rounded()
        let goalProtein = (weight * (goal == .maintain ? 0.8 : 1.6)).rounded()

        return DailyTargets(
            maintenanceKcal: maintenance.rounded(),
            kcal: energy,
            protein: goalProtein,
            proteinMinimum: minimumProtein,
            proteinRange: gramRange(energy: energy, lowerShare: 0.10, upperShare: 0.35, kcalPerGram: 4),
            carbohydrateRange: gramRange(energy: energy, lowerShare: 0.45, upperShare: 0.65, kcalPerGram: 4),
            fatRange: gramRange(energy: energy, lowerShare: 0.20, upperShare: 0.35, kcalPerGram: 9),
            salt: saltCeilingGrams,
            goalAdjustmentKcal: (energy - maintenance).rounded()
        )
    }

    /// Adult (19+) EER/TEE equations from the 2023 Dietary Reference Intakes
    /// for Energy. Age is in years, height in centimetres and weight in kg.
    public static func maintenanceEnergy(for profile: NutritionProfile) -> Double? {
        guard profile.hasValidBodyInputs,
              let age = profile.ageYears.map(Double.init),
              let height = profile.heightCentimeters,
              let weight = profile.weightKilograms,
              let sex = profile.referenceSex,
              let activity = profile.activityLevel
        else { return nil }

        let coefficients: (intercept: Double, age: Double, height: Double, weight: Double)
        switch (sex, activity) {
        case (.male, .inactive): coefficients = (753.07, -10.83, 6.50, 14.10)
        case (.male, .lowActive): coefficients = (581.47, -10.83, 8.30, 14.94)
        case (.male, .active): coefficients = (1_004.82, -10.83, 6.52, 15.91)
        case (.male, .veryActive): coefficients = (-517.88, -10.83, 15.61, 19.11)
        case (.female, .inactive): coefficients = (584.90, -7.01, 5.72, 11.71)
        case (.female, .lowActive): coefficients = (575.77, -7.01, 6.60, 12.14)
        case (.female, .active): coefficients = (710.25, -7.01, 6.54, 12.34)
        case (.female, .veryActive): coefficients = (511.83, -7.01, 9.07, 12.56)
        }
        return coefficients.intercept
            + coefficients.age * age
            + coefficients.height * height
            + coefficients.weight * weight
    }

    private static func gramRange(
        energy: Double,
        lowerShare: Double,
        upperShare: Double,
        kcalPerGram: Double
    ) -> ClosedRange<Double> {
        (energy * lowerShare / kcalPerGram).rounded()
            ...
            (energy * upperShare / kcalPerGram).rounded()
    }

    /// Individual energy needs vary around the population equation. The band
    /// is presentation uncertainty, not permission to treat either edge as a
    /// hard daily limit.
    public static let energyBand = 0.10

    public var kcalRange: ClosedRange<Double> {
        (kcal * (1 - Self.energyBand)).rounded()...(kcal * (1 + Self.energyBand)).rounded()
    }
}
