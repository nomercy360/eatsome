import Foundation
import Testing
@testable import ShamanCore

@Suite("Diet scoring")
struct DietTests {
    /// Every assertion below the fixtures was written against `MedasScorer` and
    /// is unchanged apart from the call. That is the point of keeping them: the
    /// Mediterranean stopped being hardcoded and must not have stopped meaning
    /// what it meant. A week that scored 13 of 13 in August scores 13 of 13 now.
    private func medas(_ meals: [MealEntry], habits: DietHabits = DietHabits()) -> DietResult {
        DietScorer(spec: DietPresets.mediterranean)
            .score(meals: meals, habits: habits, windowEnd: now)
    }

    private func goal(_ result: DietResult, _ id: String) -> DietResult.GoalResult {
        result.goals.first { $0.id == id }!
    }

    @Test("Regrouping an edited list keeps each dish's count and loses nothing")
    func regroupAfterACorrection() {
        let original = [
            MealDish(name: "fried rice", count: 2, items: [
                MealItem(group: .refinedGrains, portion: .medium, label: "rice"),
                MealItem(group: .whiteMeat, portion: .small, label: "chicken")
            ]),
            MealDish(name: "beer", count: 3, items: [
                MealItem(group: .alcohol, portion: .medium, label: "beer")
            ])
        ]
        var flat = original.flatMap { $0.flattened() }
        // A correction adds a food, and the delta knows nothing about dishes.
        flat.append(MealItem(group: .oliveOil, portion: .small, label: "oil it was fried in"))

        let regrouped = MealDish.regrouped(flat, keeping: original)
        #expect(regrouped.map(\.name) == ["fried rice", "beer", ""])
        // Counts survive: no flat row carries them.
        #expect(regrouped.map(\.count) == [2, 3, 1])

        // Flattening again must not apply the count twice.
        let again = regrouped.flatMap { $0.flattened() }
        #expect(again.filter { $0.group == .alcohol }.map(\.servings) == [3])
        #expect(again.filter { $0.group == .refinedGrains }.map(\.servings) == [2])
        #expect(again.count == flat.count)
    }

    @Test("The flat list is exactly what the dishes imply, and only they write it")
    func flattenedMatchesDishes() {
        // Both are stored: dishes so the meal reads, items so a build that has
        // never heard of a dish still scores it. They can only disagree if
        // something writes one without the other.
        let dishes = [
            MealDish(
                name: "fried rice",
                count: 2,
                size: .medium,
                items: [
                    MealItem(group: .refinedGrains, portion: .medium, label: "rice"),
                    MealItem(group: .whiteMeat, portion: .small, label: "chicken")
                ]
            ),
            MealDish(
                name: "beer",
                count: 3,
                items: [MealItem(group: .alcohol, portion: .medium, label: "beer")]
            )
        ]
        let meal = MealEntry(
            eatenAt: 0,
            items: dishes.flatMap { $0.flattened() },
            source: .photo,
            storedDishes: dishes
        )

        #expect(meal.items.map(\.servings) == [2, 1, 3])
        #expect(meal.items.map(\.dish) == ["fried rice", "fried rice", "beer"])
        #expect(meal.rawServings(of: .whiteMeat) == 1)
        // 3 × 2 for the rice, 26 × 1 for the chicken, alcohol contributes none.
        #expect(Protein.grams(in: meal) == 6 + 26)

        // The two representations agree, which is the property worth guarding.
        let reflattened = meal.storedDishes?.flatMap { $0.flattened() } ?? []
        #expect(reflattened.map(\.servings) == meal.items.map(\.servings))
        #expect(reflattened.map(\.group) == meal.items.map(\.group))
    }

    @Test("A dish groups its ingredients, and old meals group under nothing")
    func dishGrouping() {
        let meal = MealEntry(
            eatenAt: 0,
            items: [
                MealItem(group: .vegetables, portion: .medium, label: "leaves", dish: "green salad", servings: 1),
                MealItem(group: .oliveOil, portion: .small, label: "dressing", dish: "green salad", servings: 0.5),
                MealItem(group: .alcohol, portion: .medium, label: "beer", dish: "beer", servings: 3),
                MealItem(group: .fruit, portion: .medium, label: "apple")
            ],
            source: .photo
        )
        #expect(meal.dishGroups.map(\.name) == ["green salad", "beer", nil])
        #expect(meal.dishGroups.first?.items.count == 2)

        // Two dressed salads must not clear the 4 tbsp/day olive oil criterion,
        // which is exactly what an ingredient portion of `small` protects.
        #expect(meal.rawServings(of: .oliveOil) == 0.5)
        // The count survives into the score, up to the per-meal cap.
        #expect(meal.rawServings(of: .alcohol) == 3)
        #expect(meal.servings(of: .alcohol) == MealScoring.perMealGroupCap)
    }

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
            if day < 2 { meals.append(.fixture(daysAgo: at, [(.cookedTomatoSauce, .medium)])) }
        }
        return meals
    }

    @Test("A compliant week scores full marks")
    func perfectWeek() {
        let result = medas(goodWeek())
        #expect(result.maxScore == 13, "13 rules; the wine item was removed, not excluded")
        #expect(result.score == 13)
        // Optional, and nil for every diet that is not a published instrument:
        // "good adherence" is PREDIMED's threshold, not this app's opinion.
        #expect(result.meetsGoodAdherence == true)
        #expect(result.daysLogged == 7)
        #expect(!result.isUnderreported)

        let failed = result.goals.filter { !$0.passed }.map(\.title)
        #expect(failed.isEmpty, "failed: \(failed)")
    }

    @Test("One heavy meat day does not fail the week")
    func rollingWindowForgivesOneDay() {
        var meals = goodWeek()
        meals.append(.fixture(daysAgo: 3.5, [(.redMeat, .large), (.redMeat, .large)]))

        let result = medas(meals)
        let redMeat = goal(result, "medas-5")
        #expect(redMeat.passed, "one heavy meal caps at 2 servings, or 0.29/day over the week")
        #expect(result.score == 13)
    }

    @Test("A sustained pattern does fail it")
    func sustainedPatternFails() {
        var meals = goodWeek()
        for day in 0..<7 {
            meals.append(.fixture(daysAgo: Double(day) + 0.5, [(.redMeat, .medium), (.processedMeat, .medium)]))
        }
        let result = medas(meals)
        #expect(!goal(result, "medas-5").passed)
        #expect(result.score == 12)
    }

    @Test("Sparse logging is flagged rather than silently scored")
    func sparseLoggingIsFlagged() {
        let meals = [MealEntry.fixture(daysAgo: 1.5, [(.vegetables, .medium)])]
        let result = medas(meals)

        #expect(result.isUnderreported)
        #expect(result.daysLogged == 1)
        // Every upper-bound rule passes for free when nothing is logged, which
        // is exactly why the flag has to exist — and why a constraint has to
        // carry it too. See `sparseLoggingDoesNotEarnAKeptPromise`.
        #expect(goal(result, "medas-5").passed)
        #expect(goal(result, "medas-7").passed)
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
            return goal(medas(meals), "medas-2").passed
        }
        #expect(!score(servingsPerDay: 1), "1 serving is 2 tbsp/day, under the 4 tbsp bar")
        #expect(score(servingsPerDay: 2))
    }

    @Test("Meals outside the window are ignored")
    func windowIsHonoured() {
        var meals = goodWeek()
        meals.append(.fixture(daysAgo: 20, [(.sugaryDrinks, .large), (.sugaryDrinks, .large)]))
        let result = medas(meals)
        #expect(result.score == 13)
    }

    @Test("Habit rules follow settings, not photographs")
    func habitsAreScored() {
        let habits = DietHabits(answers: [
            DietPresets.oliveOilIsMainFatHabit: false,
            DietPresets.prefersWhiteMeatHabit: false
        ])
        let result = medas(goodWeek(), habits: habits)
        #expect(result.score == 11)
        #expect(!goal(result, "medas-1").passed)
        #expect(!goal(result, "medas-13").passed)
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
        let fruit = goal(medas(meals), "medas-4")
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
        // No MEDAS rule scores it, which is the point: filing it under fruit
        // would credit a fruit serving that was never eaten.
        let medas = DietPresets.mediterranean
        #expect(medas.footprint(of: .plantFats).isUnscored)
        #expect(medas.choiceChangesScore(.plantFats, .fruit))
        #expect(medas.choiceChangesScore(.plantFats, .vegetables))
        #expect(FoodGroup.plantFats.commonlyConfusedWith.contains(.fruit))
    }

    // MARK: - What the old engine could not say

    @Test("Switching diet re-scores the same history, with no photograph re-read")
    func switchingRescoresHistory() {
        // One week of meals, two diets, two verdicts. Nothing about the meals
        // changed — this is the whole claim the diet engine rests on.
        let meals = goodWeek()
        let mediterranean = DietScorer(spec: DietPresets.mediterranean)
            .score(meals: meals, habits: DietHabits(), windowEnd: now)
        let keto = DietScorer(spec: DietPresets.ketoStyle)
            .score(meals: meals, habits: DietHabits(), windowEnd: now)

        #expect(mediterranean.score == mediterranean.maxScore)
        #expect(keto.score < keto.maxScore, "a Mediterranean week is not a keto week")
        // Fruit three times a day is a goal under one and a limit under the
        // other, off the same rows.
        #expect(goal(mediterranean, "medas-4").passed)
        #expect(!goal(keto, "keto-fruit").passed)
    }

    @Test("Olives are the one figure every diet shares")
    func olivesAreComparableAcrossDiets() {
        let half = DietScorer(spec: DietPresets.mediterranean)
            .score(meals: goodWeek(), habits: DietHabits(), windowEnd: now)
        #expect(half.olives == 5.0)

        let nothing = DietScorer(spec: DietPresets.mediterranean)
            .score(meals: [], habits: DietHabits(answers: [
                DietPresets.oliveOilIsMainFatHabit: false,
                DietPresets.prefersWhiteMeatHabit: false
            ]), windowEnd: now)
        // Five upper bounds pass for free on an empty week; the habits do not.
        #expect(nothing.olives > 0 && nothing.olives < 5)
        #expect(nothing.isUnderreported, "and the week says so rather than showing the figure")
    }

    // MARK: - never

    /// A week a vegetarian would call a good one. Deliberately not `goodWeek()`:
    /// that one has fish in it three times, which is a MEDAS rule and a broken
    /// promise, and the difference is the entire point of the two kinds of rule.
    private func meatlessWeek() -> [MealEntry] {
        var meals: [MealEntry] = []
        for day in 0..<7 {
            let at = Double(day) + 0.5
            meals.append(.fixture(daysAgo: at, [
                (.vegetables, .medium), (.vegetables, .medium),
                (.wholeGrains, .medium), (.fruit, .medium)
            ]))
            meals.append(.fixture(daysAgo: at + 0.1, [(.fruit, .medium)]))
            if day < 4 { meals.append(.fixture(daysAgo: at + 0.2, [(.legumes, .medium)])) }
            if day < 3 { meals.append(.fixture(daysAgo: at + 0.3, [(.nuts, .medium)])) }
        }
        return meals
    }

    @Test("An exclusion is reported, never averaged, and names the dish")
    func neverIsAConstraintNotAGoal() {
        var meals = meatlessWeek()
        meals.append(MealEntry(
            eatenAt: now - 2 * 86_400_000,
            items: [MealItem(group: .whiteMeat, label: "chicken stock", dish: "soup", grams: 20)],
            source: .photo
        ))

        let result = DietScorer(spec: DietPresets.vegetarian)
            .score(meals: meals, habits: DietHabits(), windowEnd: now)

        // The goals are untouched: this is the "4.5 olives but there was
        // chicken stock in the soup" case, and the olives must not move.
        let clean = DietScorer(spec: DietPresets.vegetarian)
            .score(meals: meatlessWeek(), habits: DietHabits(), windowEnd: now)
        #expect(clean.brokenConstraints.isEmpty)
        #expect(result.score == clean.score)
        #expect(result.olives == clean.olives)

        let broken = result.brokenConstraints
        #expect(broken.map(\.id) == ["veg-no-meat"])
        #expect(broken.first?.breaks.count == 1)
        #expect(broken.first?.breaks.first?.dish == "soup")
        #expect(broken.first?.breaks.first?.group == .whiteMeat)
        #expect(result.constraints.first { $0.id == "veg-no-fish" }?.isKept == true)
    }

    @Test("`never` is not `dailyBelow(0)`, which can never pass")
    func neverIsExpressibleAtAll() {
        // The old shapes were all strictly-less-than or at-least, so "none of
        // this, ever" had no expression: `dailyBelow(meat, 0)` is `0 < 0`.
        let empty = DietScorer(spec: DietPresets.vegetarian)
            .score(meals: [MealEntry.fixture(daysAgo: 1, [(.legumes, .medium)])],
                   habits: DietHabits(), windowEnd: now)
        #expect(empty.constraints.filter { !$0.isKept }.isEmpty)
        #expect(empty.constraints.count == 2)
    }

    @Test("One meal is one broken promise, however many rows it was split into")
    func aBrokenPromiseIsCountedPerMeal() {
        let bolognese = MealEntry(
            eatenAt: now - 86_400_000,
            items: [
                MealItem(group: .redMeat, label: "mince", dish: "bolognese", grams: 120),
                MealItem(group: .redMeat, label: "pancetta", dish: "bolognese", grams: 30),
                MealItem(group: .processedMeat, label: "bacon", dish: "bolognese", grams: 20)
            ],
            source: .photo
        )
        let result = DietScorer(spec: DietPresets.vegetarian)
            .score(meals: [bolognese], habits: DietHabits(), windowEnd: now)
        #expect(result.brokenConstraints.first?.breaks.count == 1, "one dinner, not three")
    }

    @Test("Sparse logging does not earn a kept promise")
    func sparseLoggingDoesNotEarnAKeptPromise() {
        // Two logged meals a week "keeps" every constraint for free. The result
        // has to carry the same annotation the score does, or a screen will
        // draw a clean week out of an unlogged one.
        let result = DietScorer(spec: DietPresets.vegetarian)
            .score(meals: [MealEntry.fixture(daysAgo: 1.5, [(.vegetables, .medium)])],
                   habits: DietHabits(), windowEnd: now)
        #expect(result.constraints.filter { !$0.isKept }.isEmpty)
        #expect(result.isUnderreported)
    }

    // MARK: - eachMeal

    @Test("A per-meal rule is not a day total")
    func eachMealIsNotADayTotal() {
        let spec = DietSpec(
            id: "t", name: "t",
            goals: [.init(id: "protein-each-meal", title: "Protein at every meal",
                          shape: .eachMeal([.fish, .whiteMeat, .egg, .dairy]))]
        )
        // Three yoghurts at breakfast and nothing at lunch: the old engine saw
        // three servings of dairy on the day and called it satisfied.
        let piled = [
            MealEntry.fixture(daysAgo: 1.1, [(.dairy, .medium), (.dairy, .medium), (.dairy, .medium)]),
            MealEntry.fixture(daysAgo: 1.2, [(.refinedGrains, .large)])
        ]
        let result = DietScorer(spec: spec).score(meals: piled, habits: DietHabits(), windowEnd: now)
        #expect(!goal(result, "protein-each-meal").passed)
        #expect(goal(result, "protein-each-meal").observed == 0.5)

        let spread = [
            MealEntry.fixture(daysAgo: 1.1, [(.dairy, .medium)]),
            MealEntry.fixture(daysAgo: 1.2, [(.fish, .medium), (.refinedGrains, .large)])
        ]
        #expect(goal(DietScorer(spec: spec).score(meals: spread, habits: DietHabits(), windowEnd: now),
                     "protein-each-meal").passed)
    }

    @Test("A black coffee is not a meal")
    func aDrinkDoesNotBreakAPerMealRule() {
        let spec = DietSpec(
            id: "t", name: "t",
            goals: [.init(id: "veg-each-meal", title: "Vegetables at every meal",
                          shape: .eachMeal([.vegetables]))]
        )
        var coffee = MealEntry(
            eatenAt: now - 86_400_000,
            items: [MealItem(group: .coffee, label: "espresso", grams: 30)],
            source: .text
        )
        coffee.share = .whole
        let lunch = MealEntry.fixture(daysAgo: 1.2, [(.vegetables, .medium), (.legumes, .medium)])

        let result = DietScorer(spec: spec)
            .score(meals: [coffee, lunch], habits: DietHabits(), windowEnd: now)
        #expect(goal(result, "veg-each-meal").passed, "a cup is under the meal floor")

        // A couple of bites of somebody else's plate is not a meal either — the
        // floor reads share-scaled servings, so `.taste` falls under it.
        var taste = MealEntry.fixture(daysAgo: 1.3, [(.refinedGrains, .medium)])
        taste.share = .taste
        #expect(goal(DietScorer(spec: spec)
            .score(meals: [taste, lunch], habits: DietHabits(), windowEnd: now),
            "veg-each-meal").passed)
    }

    // MARK: - eatingWindow

    @Test("An eating window is read in local hours, and wraps midnight")
    func eatingWindowUsesLocalHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        func meal(atHour hour: Int) -> MealEntry {
            let day = calendar.startOfDay(for: Date(epochMillis: now - 2 * 86_400_000))
            return MealEntry(
                eatenAt: day.addingTimeInterval(Double(hour) * 3600).epochMillis,
                items: [MealItem(group: .refinedGrains, label: "toast", grams: 80)],
                source: .text
            )
        }

        let fasting = DietSpec(
            id: "t", name: "t", goals: [],
            constraints: [.init(id: "window", title: "Eating window",
                                shape: .eatingWindow(startHour: 12, endHour: 20))]
        )
        let result = DietScorer(spec: fasting).score(
            meals: [meal(atHour: 9), meal(atHour: 13), meal(atHour: 21)],
            habits: DietHabits(), windowEnd: now, calendar: calendar
        )
        #expect(result.constraints.first?.breaks.count == 2, "09:00 and 21:00 are outside")

        // A window that runs past midnight is two intervals on the clock and
        // one to a person.
        let nightShift = DietSpec(
            id: "t", name: "t", goals: [],
            constraints: [.init(id: "window", title: "Eating window",
                                shape: .eatingWindow(startHour: 20, endHour: 4))]
        )
        let overnight = DietScorer(spec: nightShift).score(
            meals: [meal(atHour: 21), meal(atHour: 2), meal(atHour: 13)],
            habits: DietHabits(), windowEnd: now, calendar: calendar
        )
        #expect(overnight.constraints.first?.breaks.count == 1, "only the 13:00 meal is outside")
    }

    // MARK: - grams

    @Test("A protein target is a goal like any other, and averages over the window")
    func proteinTargetIsAGoal() {
        let spec = DietPresets.mediterranean.withProteinTarget(90)
        #expect(spec.proteinTarget == 90)
        #expect(spec.goals.count == DietPresets.mediterranean.goals.count + 1)

        // 7 x 200 g of fish at 22 g/100 g is 44 g a day, well short.
        let thin = (0..<7).map { day in
            MealEntry(
                eatenAt: now - EpochMillis(day) * 86_400_000 - 43_200_000,
                items: [MealItem(group: .fish, label: "cod", grams: 200)],
                source: .photo
            )
        }
        let result = DietScorer(spec: spec).score(meals: thin, habits: DietHabits(), windowEnd: now)
        let protein = goal(result, DietPresets.proteinGoalID)
        #expect(!protein.passed)
        #expect(protein.observed > 40 && protein.observed < 50)

        // A target met on the two days somebody remembered to log is not a
        // target met: the average is over the window, not over logged days.
        // 1 kg of cod is 220 g of protein — 110 g a day over two days and 63 g
        // a day over the week that actually happened.
        let twoBigDays = (0..<2).map { day in
            MealEntry(
                eatenAt: now - EpochMillis(day) * 86_400_000 - 43_200_000,
                items: [MealItem(group: .fish, label: "cod", grams: 1_000)],
                source: .photo
            )
        }
        #expect(!goal(DietScorer(spec: spec).score(meals: twoBigDays, habits: DietHabits(), windowEnd: now),
                      DietPresets.proteinGoalID).passed)

        #expect(DietPresets.mediterranean.withProteinTarget(nil).proteinTarget == nil)
    }

    // MARK: - Which questions are worth asking

    @Test("Which ambiguity earns a tap is computed from the active diet")
    func questionsFollowTheDiet() {
        let medas = DietPresets.mediterranean
        let lowSugar = DietPresets.lowSugar

        // MEDAS scores red meat and not white, so the pair is a real question,
        // and scores no grain at all, so that pair is not.
        #expect(medas.choiceChangesScore(.whiteMeat, .redMeat))
        #expect(!medas.choiceChangesScore(.wholeGrains, .refinedGrains))

        // Low-sugar has no meat rule and rules on both grains and both sweet
        // drinks — so the app stops asking one question and starts asking
        // another, with no new code.
        #expect(!lowSugar.choiceChangesScore(.whiteMeat, .redMeat))
        #expect(lowSugar.choiceChangesScore(.wholeGrains, .refinedGrains))
        #expect(lowSugar.choiceChangesScore(.juice, .sugaryDrinks))
    }

    @Test("Two foods under the same exclusion stop being a question")
    func rivalsInsideOneConstraintAreNotWorthATap() {
        let vegetarian = DietPresets.vegetarian
        // Pork read as chicken breaks the same promise either way, so asking
        // which animal it was is asking a question whose answer changes nothing
        // the person is being told.
        #expect(!vegetarian.choiceChangesScore(.redMeat, .whiteMeat))
        // Fish against meat crosses two different constraints, and does.
        #expect(vegetarian.choiceChangesScore(.fish, .whiteMeat))
        #expect(vegetarian.choiceChangesScore(.whiteMeat, .legumes))
    }

    @Test("A protein target does not turn every ambiguity into a question")
    func nutrientRulesDoNotSaturateTheQuestionBudget() {
        let spec = DietPresets.mediterranean.withProteinTarget(90)
        // Nearly every pair of groups differs in protein density, so folding a
        // gram rule into the footprint would make every ambiguity "score
        // changing" and the filter would stop filtering.
        #expect(!spec.choiceChangesScore(.wholeGrains, .refinedGrains))
        // Quantity is what decides it instead: a garnish cannot move a 90 g
        // target, a main can.
        #expect(!spec.choiceChangesNutrients(.fish, .refinedGrains, grams: 10))
        #expect(spec.choiceChangesNutrients(.fish, .refinedGrains, grams: 200))
        // And with no target set, the question never arises.
        #expect(!DietPresets.mediterranean.choiceChangesNutrients(.fish, .refinedGrains, grams: 200))
    }

    // MARK: - Forking, and what survives a round trip

    @Test("A fork is self-contained and does not inherit the instrument badge")
    func forkingDropsTheValidatedClaim() {
        let fork = DietPresets.vegetarian.forked(as: "Anya's plan", id: "anya")
        #expect(fork.instrument == nil, "validated means a published screener, not a name")
        #expect(fork.forkedFrom == "vegetarian")
        #expect(fork.goals.count == DietPresets.vegetarian.goals.count)
        #expect(fork.constraints.count == DietPresets.vegetarian.constraints.count)
        #expect(DietPresets.mediterranean.instrument == "MEDAS")
    }

    @Test("A saved diet survives the log, every shape of rule intact")
    func specRoundTripsThroughTheEventLog() throws {
        var spec = DietPresets.vegetarian.forked(as: "Anya's plan", id: "anya")
        spec.goals.append(.init(id: "eggs-each-meal", title: "Eggs or dairy at every meal",
                                shape: .eachMeal([.egg, .dairy])))
        spec.constraints.append(.init(id: "window", title: "Eating window",
                                      shape: .eatingWindow(startHour: 12, endHour: 20),
                                      isEnabled: false))
        spec = spec.withProteinTarget(90)

        let event = LoggedEvent(occurredAt: now, payload: .dietSaved(spec))
        let data = try JSONEncoder().encode(event)
        let back = try JSONDecoder().decode(LoggedEvent.self, from: data)
        guard case .dietSaved(let decoded) = back.payload else {
            Issue.record("not a dietSaved"); return
        }
        #expect(decoded == spec)

        var projection = Projection()
        projection.apply(back)
        projection.apply(LoggedEvent(occurredAt: now, payload: .dietSelected(dietID: "anya")))
        #expect(projection.diet.id == "anya")
        #expect(projection.diet.proteinTarget == 90)
        #expect(projection.availableDiets.count == DietPresets.all.count + 1)
    }

    @Test("No diet selected is Mediterranean, and a diet that vanished is too")
    func theDefaultIsAFactAboutTheReader() {
        var projection = Projection()
        #expect(projection.diet.id == "mediterranean")
        projection.apply(LoggedEvent(occurredAt: now, payload: .dietSelected(dietID: "a-diet-this-build-lost")))
        #expect(projection.diet.id == "mediterranean", "an unscored week looks like a week nobody ate in")
    }

    @Test("The two old habit booleans still answer the two MEDAS questions")
    func legacyHabitsDecode() throws {
        // A `habits_updated` line written before habits were a bag.
        let legacy = Data(#"{"oliveOilIsMainCulinaryFat":false,"prefersWhiteMeatOverRed":true}"#.utf8)
        let habits = try JSONDecoder().decode(DietHabits.self, from: legacy)
        #expect(!habits.answer(id: DietPresets.oliveOilIsMainFatHabit))
        #expect(habits.answer(id: DietPresets.prefersWhiteMeatHabit))

        // And a line written now still carries them, so an older build reading
        // it does not silently revert to both-true and gain two points.
        let round = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(habits)) as? [String: Any]
        #expect(round?["oliveOilIsMainCulinaryFat"] as? Bool == false)
        #expect(round?["answers"] != nil)
    }

    // MARK: - The rename

    @Test("A meal logged under the old group names still decodes and still scores")
    func legacyFoodGroupNamesSurvive() throws {
        let line = Data(#"""
        {"id":"018F0000-0000-7000-8000-000000000001","group":"sofrito","portion":"medium","grams":100}
        """#.utf8)
        let item = try JSONDecoder().decode(MealItem.self, from: line)
        #expect(item.group == .cookedTomatoSauce)

        let fats = try JSONDecoder().decode(
            MealItem.self,
            from: Data(#"{"id":"018F0000-0000-7000-8000-000000000002","group":"healthy_fats","portion":"medium"}"#.utf8)
        )
        #expect(fats.group == .plantFats)

        // A group this build has never heard of lands in `other` rather than
        // taking the whole meal down with it.
        let future = try JSONDecoder().decode(
            MealItem.self,
            from: Data(#"{"id":"018F0000-0000-7000-8000-000000000003","group":"seaweed","portion":"medium"}"#.utf8)
        )
        #expect(future.group == .other)
    }

    @Test("Every table still answers to both spellings")
    func renamedGroupsResolveInEveryTable() throws {
        // The silent-miss failure this whole rename had to avoid: a config
        // fetched by a build of any age keys these tables by raw value, and a
        // miss is not an error — it is a wrong number with no error anywhere.
        for group in [FoodGroup.cookedTomatoSauce, .plantFats] {
            for name in group.storedNames {
                #expect(ServingWeight.defaultGrams[name] != nil || group.value(in: ServingWeight.defaultGrams) != nil)
            }
            #expect(group.value(in: ServingWeight.defaultGrams) != nil, "\(group) has no serving weight")
            #expect(group.value(in: Protein.defaultGramsPerServing) != nil, "\(group) has no protein figure")
        }

        // A config still spelling the old names — which is every config already
        // cached on a phone — must resolve exactly as the new one does.
        let legacyOlives = OliveConfiguration(weights: ["sofrito": 0.5, "healthy_fats": 0.25])
        #expect(legacyOlives.weight(for: .cookedTomatoSauce) == 0.5)
        #expect(legacyOlives.weight(for: .plantFats) == 0.25)
        #expect(ServingWeight.servings(fromGrams: 100, of: .cookedTomatoSauce, table: ["sofrito": 50]) == 2)

        // And the new group is not a 100 g fallback pretending to be a serving.
        #expect(ServingWeight.defaultGrams[FoodGroup.vegetableOil.rawValue] == 10)
    }

    @Test("A rule reads as a sentence even when nobody wrote one for it")
    func copyIsGeneratedFromTheTemplate() {
        // MEDAS keeps its hand-written lines.
        let medas = DietPresets.mediterranean
        #expect(DietCopy.plainTitle(medas.goal(id: "medas-3")!, in: medas) == "Vegetables, twice a day")

        // Anything assembled from steppers gets a sentence rather than a
        // threshold — which is what "copy per rule template" buys.
        let built = DietGoal(id: "x", title: "Legumes ≥ 4 servings/week",
                             shape: .weeklyAtLeast([.legumes], 4.0))
        #expect(DietCopy.plainTitle(built) == "Beans, four a week")
        #expect(DietCopy.plainTitle(DietGoal(id: "y", title: "", shape: .dailyBelow([.sweets, .pastry], 3))) ==
                "Sweets and pastry")
        #expect(DietCopy.plainTitle(DietGoal(id: "z", title: "", shape: .eachMeal([.egg, .dairy]))) ==
                "Eggs and dairy at every meal")
    }
}
