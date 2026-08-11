import Foundation
import Testing
@testable import ShamanCore

@Suite("Daily nutrition references")
struct DailyTargetsTests {
    private let base = NutritionProfile(
        ageYears: 30,
        referenceSex: .male,
        heightCentimeters: 180,
        weightKilograms: 80,
        bodyFatPercentage: 20,
        activityLevel: .lowActive,
        goal: .maintain
    )

    @Test("The 2023 adult equations use the published coefficients")
    func maintenanceEnergy() {
        // 581.47 − 10.83×30 + 8.30×180 + 14.94×80
        let energy = DailyTargets.maintenanceEnergy(for: base)
        #expect(energy != nil)
        #expect(abs((energy ?? 0) - 2_945.77) < 0.001)

        var female = base
        female.ageYears = 45
        female.referenceSex = .female
        female.heightCentimeters = 165.1
        female.weightKilograms = 59
        female.activityLevel = .active
        // 710.25 − 7.01×45 + 6.54×165.1 + 12.34×59
        #expect(abs((DailyTargets.maintenanceEnergy(for: female) ?? 0) - 2_202.614) < 0.001)
    }

    @Test("A missing or out-of-scope body input produces no reference")
    func completeness() {
        var profile = base
        profile.ageYears = nil
        #expect(DailyTargets.forProfile(profile) == nil)

        profile.ageYears = 18
        #expect(DailyTargets.forProfile(profile) == nil)

        profile.ageYears = 30
        profile.goal = nil
        #expect(DailyTargets.forProfile(profile) == nil)
    }

    @Test("Maintain, lose and muscle-gain goals stay visibly tied to maintenance")
    func goals() throws {
        let maintain = try #require(DailyTargets.forProfile(base))
        #expect(maintain.maintenanceKcal == 2_946)
        #expect(maintain.kcal == 2_946)
        #expect(maintain.goalAdjustmentKcal == 0)
        #expect(maintain.protein == 64)

        var lossProfile = base
        lossProfile.goal = .loseWeight
        let loss = try #require(DailyTargets.forProfile(lossProfile))
        #expect(loss.kcal == 2_446)
        #expect(loss.goalAdjustmentKcal == -500)
        #expect(loss.protein == 128)

        var gainProfile = base
        gainProfile.goal = .gainMuscle
        let gain = try #require(DailyTargets.forProfile(gainProfile))
        #expect(gain.kcal == 3_240)
        #expect(gain.goalAdjustmentKcal == 294)
        #expect(gain.protein == 128)
    }

    @Test("Macro references retain the adult acceptable ranges")
    func macroRanges() throws {
        var profile = base
        profile.goal = .loseWeight
        let targets = try #require(DailyTargets.forProfile(profile))
        #expect(targets.proteinRange == 61...214)
        #expect(targets.carbohydrateRange == 275...397)
        #expect(targets.fatRange == 54...95)
        #expect(targets.salt == 5)
    }

    @Test("An underweight entry does not receive an automatic deficit")
    func noAutomaticUnderweightDeficit() throws {
        var profile = base
        profile.referenceSex = .female
        profile.heightCentimeters = 170
        profile.weightKilograms = 45
        profile.goal = .loseWeight
        let targets = try #require(DailyTargets.forProfile(profile))
        #expect(targets.kcal == targets.maintenanceKcal)
        #expect(targets.goalAdjustmentKcal == 0)
    }

    @Test("Body fat is optional and only supplies approximate lean mass")
    func leanMass() {
        #expect(base.leanMassKilograms == 64)
        var withoutBodyFat = base
        withoutBodyFat.bodyFatPercentage = nil
        #expect(withoutBodyFat.leanMassKilograms == nil)
        #expect(DailyTargets.maintenanceEnergy(for: withoutBodyFat)
            == DailyTargets.maintenanceEnergy(for: base))
    }

    @Test("PAL thresholds map to the four published activity categories")
    func activityInference() {
        #expect(NutritionProfile.ActivityLevel.inferred(fromPAL: 1.52) == .inactive)
        #expect(NutritionProfile.ActivityLevel.inferred(fromPAL: 1.53) == .lowActive)
        #expect(NutritionProfile.ActivityLevel.inferred(fromPAL: 1.68) == .active)
        #expect(NutritionProfile.ActivityLevel.inferred(fromPAL: 1.85) == .veryActive)
    }
}
