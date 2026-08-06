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

    @Test("A described dish is counted whole, with no share taken off it")
    func dishIsOneServingOfItself() {
        // The dishes screen counts a recipe as written. Halving belongs to the
        // meal you log from it, which is where `share` lives.
        let soup: [MealItem] = [
            MealItem(group: .legumes, portion: .large),   // 8 × 2
            MealItem(group: .vegetables, portion: .medium) // 2 × 1
        ]
        #expect(Protein.grams(in: soup) == 18)

        var half = MealEntry.fixture(daysAgo: 0, [(.legumes, .large), (.vegetables, .medium)])
        half.share = .part
        #expect(Protein.grams(in: half) == 9)
    }

    @Test("A counted dish contributes its count, not its portion")
    func countedDish() {
        // Three beers arrive as one dish with count 3, flattened to servings 3.0.
        // No case of `Portion` can say three, which is why the field exists.
        let beers = MealItem(group: .alcohol, portion: .medium, label: "beer", dish: "beer", servings: 3)
        #expect(beers.effectiveServings == 3)

        // A meal from before dishes has no servings and is unchanged by any of this.
        let legacy = MealItem(group: .fish, portion: .large)
        #expect(legacy.effectiveServings == Portion.large.servings)

        let dinner = MealEntry(
            eatenAt: 0,
            items: [
                MealItem(group: .whiteMeat, portion: .medium, dish: "fried rice", servings: 2),
                MealItem(group: .refinedGrains, portion: .medium, dish: "fried rice", servings: 2)
            ],
            source: .photo
        )
        // 26 × 2 for the meat, 3 × 2 for the rice.
        #expect(Protein.grams(in: dinner) == 52 + 6)
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

    @Test("A transcribed panel is kept, and nothing totals it")
    func caloriesAreStoredNeverSummed() throws {
        // The rule used to be that a calorie figure could not exist anywhere.
        // It can now be transcribed off a label, because reading a printed fact
        // is not estimating one — but nothing may add them up. Only packaged
        // food carries a label, so a total would be computed from the packaged
        // fraction of a diet while looking exactly like a total.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ShamanCore")
        let files = FileManager.default
            .enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)

        for file in files {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for banned in ["caloriesToday", "totalCalories", "sumCalories", "caloriesPer"] {
                #expect(!text.contains(banned), "\(file.lastPathComponent) aggregates calories")
            }
        }

        // Protein is the one figure with a complete baseline — every meal has
        // an estimate — so a confirmed value improves that total instead of
        // creating a partial one. That is the whole difference.
        let carton = MealDish(
            name: "protein drink",
            count: 2,
            size: .small,
            panel: NutritionPanel(protein: 15, calories: 103),
            items: [MealItem(group: .dairy, portion: .medium, label: "milk protein")]
        )
        #expect(Protein.grams(in: carton) == 30)
        // Size is ignored for a packaged serving; the table would have said 4.
        #expect(Protein.grams(in: MealDish(name: "x", size: .small, items: carton.items)) == 4)
    }
}
