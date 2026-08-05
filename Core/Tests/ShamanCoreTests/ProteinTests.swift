import Foundation
import Testing
@testable import ShamanCore

@Suite("Protein")
struct ProteinTests {
    @Test("A meal sums its groups by portion")
    func sumsAcrossItems() {
        let dinner = MealEntry.fixture(daysAgo: 0, [
            (.fish, .large),       // 22 × 2
            (.wholeGrains, .medium), // 4 × 1
            (.vegetables, .small)   // 2 × 0.5
        ])
        #expect(Protein.grams(in: dinner) == 44 + 4 + 1)
    }

    @Test("Eating half the plate is half the protein")
    func sharedPlate() {
        var shared = MealEntry.fixture(daysAgo: 0, [(.whiteMeat, .medium)])
        shared.share = .part
        #expect(Protein.grams(in: shared) == 13)
    }

    @Test("The MEDAS per-meal cap does not apply to protein")
    func capIsForScoringOnly() {
        // Four fillets on one platter score as one plate of fish, but you still
        // ate four fillets' worth of protein.
        let platter = MealEntry.fixture(
            daysAgo: 0,
            Array(repeating: (FoodGroup.fish, Portion.medium), count: 4)
        )
        #expect(platter.servings(of: .fish) == MealScoring.perMealGroupCap)
        #expect(Protein.grams(in: platter) == 88)
    }

    @Test("The daily target follows body weight and intent")
    func target() {
        #expect(Protein.dailyTarget(weightKilograms: 79.4, intent: .building) == 159)
        #expect(Protein.dailyTarget(weightKilograms: 79.4, intent: .active) == 127)
        #expect(Protein.dailyTarget(weightKilograms: 79.4, intent: .maintain) == 95)
        #expect(Protein.Intent.building.gramsPerKilogram == 2.0)
    }

    @Test("Every food group has a value, and the fats have none")
    func tableIsComplete() {
        for group in FoodGroup.allCases {
            #expect(
                Protein.defaultGramsPerServing[group.rawValue] != nil,
                "\(group.rawValue) is missing from the protein table"
            )
        }
        #expect(Protein.defaultGramsPerServing[FoodGroup.oliveOil.rawValue] == 0)
        #expect(Protein.defaultGramsPerServing[FoodGroup.alcohol.rawValue] == 0)
    }

    @Test("A configured table overrides the compiled one")
    func configurableTable() {
        let meal = MealEntry.fixture(daysAgo: 0, [(.egg, .medium)])
        #expect(Protein.grams(in: meal) == 6)
        #expect(Protein.grams(in: meal, gramsPerServing: ["egg": 13]) == 13)
        #expect(AppConfig.fallback.proteinTable[FoodGroup.egg.rawValue] == 6)
    }

    @Test("Nothing anywhere computes calories")
    func noCalories() {
        // The exception is protein, and it stays an exception. A kcal figure is
        // the point where this stops being the app it set out to be.
        let sources = ["Protein.swift", "Medas.swift", "Meal.swift", "FoodGroup.swift"]
        for name in sources {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()      // ShamanCoreTests
                .deletingLastPathComponent()      // Tests
                .deletingLastPathComponent()      // Core
                .appendingPathComponent("Sources/ShamanCore")
            let candidates = ["Nutrition/\(name)", "Model/\(name)"].map(url.appendingPathComponent)
            guard let text = candidates.compactMap({ try? String(contentsOf: $0, encoding: .utf8) }).first else {
                continue
            }
            // The word appears in comments explaining why there are none, which
            // is the point. A unit does not.
            #expect(!text.lowercased().contains("kcal"), "\(name) mentions kcal")
            #expect(!text.lowercased().contains("caloriesper"), "\(name) computes calories")
        }
    }
}
