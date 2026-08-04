import Foundation
import Testing
@testable import ShamanCore

@Suite("MEDAS adherence")
struct MedasTests {
    private let now = MealEntry.referenceNow

    /// A week that satisfies every scored item.
    private func goodWeek() -> [MealEntry] {
        var meals: [MealEntry] = []
        for day in 0..<7 {
            let at = Double(day) + 0.5
            meals.append(.fixture(daysAgo: at, [
                (.vegetables, .medium), (.vegetables, .medium),
                (.fruit, .medium), (.fruit, .medium), (.fruit, .medium),
                (.oliveOil, .medium), (.oliveOil, .medium)
            ]))
            if day < 3 { meals.append(.fixture(daysAgo: at, [(.fish, .medium)])) }
            if day < 3 { meals.append(.fixture(daysAgo: at, [(.legumes, .medium)])) }
            if day < 3 { meals.append(.fixture(daysAgo: at, [(.nuts, .medium)])) }
            if day < 2 { meals.append(.fixture(daysAgo: at, [(.sofrito, .medium)])) }
        }
        return meals
    }

    @Test("A compliant week scores full marks")
    func perfectWeek() {
        let result = MedasScorer().score(meals: goodWeek(), habits: DietHabits(), windowEnd: now)
        #expect(result.maxScore == 13, "wine is excluded by default")
        #expect(result.score == 13)
        #expect(result.meetsGoodAdherence)
        #expect(result.daysLogged == 7)
        #expect(!result.isUnderreported)

        let failed = result.items.filter { !$0.passed }.map(\.title)
        #expect(failed.isEmpty, "failed: \(failed)")
    }

    @Test("Wine is excluded by default and includable by configuration")
    func wineIsOptional() {
        let scored = MedasScorer(configuration: .init(excludedItems: []))
            .score(meals: goodWeek(), habits: DietHabits(), windowEnd: now)
        #expect(scored.maxScore == 14)
        #expect(scored.score == 13, "no wine logged, so the wine item fails")
        #expect(scored.items.contains { $0.id == 8 })
    }

    @Test("One heavy meat day does not fail the week")
    func rollingWindowForgivesOneDay() {
        var meals = goodWeek()
        meals.append(.fixture(daysAgo: 3.5, [(.redMeat, .large), (.redMeat, .large)]))

        let result = MedasScorer().score(meals: meals, habits: DietHabits(), windowEnd: now)
        let redMeat = result.items.first { $0.id == 5 }!
        #expect(redMeat.passed, "4 servings across 7 days averages 0.57/day, under the 1/day bound")
        #expect(result.score == 13)
    }

    @Test("A sustained pattern does fail it")
    func sustainedPatternFails() {
        var meals = goodWeek()
        for day in 0..<7 {
            meals.append(.fixture(daysAgo: Double(day) + 0.5, [(.redMeat, .medium), (.processedMeat, .medium)]))
        }
        let result = MedasScorer().score(meals: meals, habits: DietHabits(), windowEnd: now)
        #expect(!result.items.first { $0.id == 5 }!.passed)
        #expect(result.score == 12)
    }

    @Test("Sparse logging is flagged rather than silently scored")
    func sparseLoggingIsFlagged() {
        let meals = [MealEntry.fixture(daysAgo: 1.5, [(.vegetables, .medium)])]
        let result = MedasScorer().score(meals: meals, habits: DietHabits(), windowEnd: now)

        #expect(result.isUnderreported)
        #expect(result.daysLogged == 1)
        // Every upper-bound item passes for free when nothing is logged, which
        // is exactly why the flag has to exist.
        #expect(result.items.first { $0.id == 5 }!.passed)
        #expect(result.items.first { $0.id == 7 }!.passed)
    }

    @Test("Olive oil is scored in tablespoons, two per serving")
    func oliveOilTablespoons() {
        func score(servingsPerDay: Int) -> Bool {
            let meals = (0..<7).map { day in
                MealEntry.fixture(
                    daysAgo: Double(day) + 0.5,
                    Array(repeating: (FoodGroup.oliveOil, Portion.medium), count: servingsPerDay)
                )
            }
            return MedasScorer().score(meals: meals, habits: DietHabits(), windowEnd: now)
                .items.first { $0.id == 2 }!.passed
        }
        #expect(!score(servingsPerDay: 1), "1 serving is 2 tbsp/day, under the 4 tbsp bar")
        #expect(score(servingsPerDay: 2))
    }

    @Test("Meals outside the window are ignored")
    func windowIsHonoured() {
        var meals = goodWeek()
        meals.append(.fixture(daysAgo: 20, [(.sugaryDrinks, .large), (.sugaryDrinks, .large)]))
        let result = MedasScorer().score(meals: meals, habits: DietHabits(), windowEnd: now)
        #expect(result.score == 13)
    }

    @Test("Habit items follow settings, not photographs")
    func habitsAreScored() {
        let habits = DietHabits(oliveOilIsMainCulinaryFat: false, prefersWhiteMeatOverRed: false)
        let result = MedasScorer().score(meals: goodWeek(), habits: habits, windowEnd: now)
        #expect(result.score == 11)
        #expect(!result.items.first { $0.id == 1 }!.passed)
        #expect(!result.items.first { $0.id == 13 }!.passed)
    }

    @Test("Large portions count double, small portions half")
    func portionWeights() {
        let meal = MealEntry.fixture(daysAgo: 1, [(.vegetables, .large), (.vegetables, .small)])
        #expect(meal.servings(of: .vegetables) == 2.5)
        #expect(meal.servings(of: .fish) == 0)
    }
}
