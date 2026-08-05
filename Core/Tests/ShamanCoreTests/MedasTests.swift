import Foundation
import Testing
@testable import ShamanCore

@Suite("MEDAS adherence")
struct MedasTests {
    private let now = MealEntry.referenceNow

    /// A week that satisfies every scored item.
    ///
    /// Fruit is spread across three meals rather than piled into one, because
    /// that is now what three servings a day means: a meal contributes at most
    /// one large portion of any group, so a platter cannot clear a daily target
    /// on its own.
    private func goodWeek() -> [MealEntry] {
        var meals: [MealEntry] = []
        for day in 0..<7 {
            let at = Double(day) + 0.5
            meals.append(.fixture(daysAgo: at, [
                (.vegetables, .medium), (.vegetables, .medium),
                (.fruit, .medium),
                (.oliveOil, .medium), (.oliveOil, .medium)
            ]))
            meals.append(.fixture(daysAgo: at + 0.1, [(.fruit, .medium)]))
            meals.append(.fixture(daysAgo: at + 0.2, [(.fruit, .medium)]))
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
        #expect(result.maxScore == 13, "13 items; the wine item was removed, not excluded")
        #expect(result.score == 13)
        #expect(result.meetsGoodAdherence)
        #expect(result.daysLogged == 7)
        #expect(!result.isUnderreported)

        let failed = result.items.filter { !$0.passed }.map(\.title)
        #expect(failed.isEmpty, "failed: \(failed)")
    }

    @Test("One heavy meat day does not fail the week")
    func rollingWindowForgivesOneDay() {
        var meals = goodWeek()
        meals.append(.fixture(daysAgo: 3.5, [(.redMeat, .large), (.redMeat, .large)]))

        let result = MedasScorer().score(meals: meals, habits: DietHabits(), windowEnd: now)
        let redMeat = result.items.first { $0.id == 5 }!
        #expect(redMeat.passed, "one heavy meal caps at 2 servings, or 0.29/day over the week")
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
        let meal = MealEntry.fixture(daysAgo: 1, [(.vegetables, .medium), (.vegetables, .small)])
        #expect(meal.rawServings(of: .vegetables) == 1.5)
        #expect(meal.servings(of: .vegetables) == 1.5)
        #expect(meal.servings(of: .fish) == 0)
    }

    @Test("One meal counts once per group, however many rows it was split into")
    func duplicateRowsDoNotStack() {
        // The fruit platter: four rows, one plate of fruit.
        let platter = MealEntry.fixture(daysAgo: 1, [
            (.fruit, .large), (.fruit, .large), (.fruit, .large), (.fruit, .medium)
        ])
        #expect(platter.rawServings(of: .fruit) == 7.0)
        #expect(platter.servings(of: .fruit) == MealScoring.perMealGroupCap)

        // Two vegetable rows on one tray are still one vegetable serving each.
        let tray = MealEntry.fixture(daysAgo: 1, [(.vegetables, .small), (.vegetables, .small)])
        #expect(tray.servings(of: .vegetables) == 1.0, "under the cap, the sum is untouched")

        // A single row is scored exactly as it always was.
        let single = MealEntry.fixture(daysAgo: 1, [(.fruit, .large)])
        #expect(single.servings(of: .fruit) == 2.0)
    }

    @Test("A platter cannot clear a daily target on its own")
    func plattersDoNotCarryTheWeek() {
        let meals = (0..<7).map { day in
            MealEntry.fixture(
                daysAgo: Double(day) + 0.5,
                Array(repeating: (FoodGroup.fruit, Portion.large), count: 4)
            )
        }
        let fruit = MedasScorer().score(meals: meals, habits: DietHabits(), windowEnd: now)
            .items.first { $0.id == 4 }!
        #expect(!fruit.passed, "one photo a day is one fruit occasion, not three servings")
        #expect(fruit.observed == 2.0)
    }

    @Test("Eating part of a shared plate halves what it contributes")
    func partialMealsCountLess() {
        var shared = MealEntry.fixture(daysAgo: 1, [(.vegetables, .medium), (.fruit, .large)])
        shared.share = .part

        #expect(shared.rawServings(of: .vegetables) == 1.0, "the plate is unchanged")
        #expect(shared.servings(of: .vegetables) == 0.5)
        #expect(shared.servings(of: .fruit) == 1.0)

        // Entries written before the switch existed are scored as they were.
        let legacy = MealEntry.fixture(daysAgo: 1, [(.vegetables, .medium)])
        #expect(legacy.share == nil)
        #expect(legacy.eaten == .whole)
        #expect(legacy.servings(of: .vegetables) == 1.0)
    }

    @Test("Avocado counts as fat, not as produce")
    func avocadoIsNotFruit() {
        // No MEDAS item scores it, which is the point: filing it under fruit
        // would credit a fruit serving that was never eaten.
        #expect(Medas.footprint(of: .healthyFats).isUnscored)
        #expect(Medas.choiceChangesScore(.healthyFats, .fruit))
        #expect(Medas.choiceChangesScore(.healthyFats, .vegetables))
        #expect(FoodGroup.healthyFats.commonlyConfusedWith.contains(.fruit))
    }
}
