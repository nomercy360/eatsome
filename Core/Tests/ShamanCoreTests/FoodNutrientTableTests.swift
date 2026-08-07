import Foundation
import Testing
@testable import ShamanCore

@Suite("Nutrients from named foods")
struct FoodNutrientTableTests {
    private func table() -> FoodNutrientTable {
        FoodNutrientTable(
            version: "test",
            groups: [
                // Stands behind every `refined_grains` label the table misses.
                "refined_grains": .init(
                    per100g: Nutrients(
                        protein: 2.69, fat: 0.28, carbohydrate: 28.17, kcal: 130, sodium: 1
                    ),
                    source: "sr:168878", basis: "analysed", name: "Rice, white, cooked"
                )
            ],
            foods: [
                "refined_grains|spaghetti": .init(
                    per100g: Nutrients(
                        protein: 5.8, fat: 0.93, carbohydrate: 30.86, kcal: 158, sodium: 1
                    ),
                    source: "sr:169737", basis: "analysed", name: "Pasta, cooked"
                ),
                "fish|mentaiko": .init(
                    per100g: Nutrients(
                        protein: 21.0, fat: 3.3, carbohydrate: 3.0, kcal: 121, sodium: 2200
                    ),
                    source: "mext:10204", basis: "analysed", name: "からしめんたいこ"
                ),
                "dairy|cream": .init(
                    per100g: Nutrients(
                        protein: 2.1, fat: 37.0, carbohydrate: 2.8, kcal: 340, sodium: 38
                    ),
                    source: "sr:170859", basis: "analysed", name: "Cream, fluid"
                )
            ]
        )
    }

    @Test("A named food beats the group table, which is the whole point")
    func namedFoodWins() {
        // The group row is 3 g per 150 g serving — a rice figure — so 200 g of
        // spaghetti derives 4 g. The measured plate was nearer 11.
        let item = MealItem(group: .refinedGrains, label: "spaghetti", grams: 200)
        let byGroup = Protein.grams(in: [item])
        let byFood = Protein.grams(in: [item], foods: table())

        #expect(byGroup == 4.0)
        #expect(byFood == 11.6)
    }

    @Test("Every figure comes off the same source row")
    func oneLookupAnswersAll() {
        // 200 g of cooked pasta, and nothing here was asked of a model: the
        // weight is an observation, the five figures are one published row.
        let item = MealItem(group: .refinedGrains, label: "spaghetti", grams: 200)
        let total = Nutrition.total(in: [item], foods: table())

        #expect(total.nutrients.protein == 11.6)
        #expect(total.nutrients.kcal == 316)
        #expect(abs(total.nutrients.carbohydrate - 61.72) < 0.001)
        #expect(abs(total.nutrients.fat - 1.86) < 0.001)
        #expect(total.isComplete)
    }

    @Test("A food the table has never heard of costs exactly what it cost before")
    func missFallsBackRatherThanZeroing() {
        let item = MealItem(group: .refinedGrains, label: "rye sourdough", grams: 200)
        // Not nil, not zero: the protein group table, unchanged. A lookup that
        // returned zero on a miss would silently delete protein from the history.
        #expect(Protein.grams(in: [item], foods: table()) == Protein.grams(in: [item]))

        // Energy has no such hand-calibrated table, so it lands on the group's
        // representative row instead of on nothing.
        let total = Nutrition.total(in: [item], foods: table())
        #expect(total.nutrients.kcal == 260)
        #expect(total.isComplete)
    }

    @Test("Unrecognised food reports no energy and says the total is short")
    func otherIsUnresolvedRatherThanZero() {
        // `other` has no representative row on purpose: a figure for food nobody
        // identified would be invented rather than estimated. The weight is
        // still counted, so the screen can say the day is incomplete instead of
        // quietly under-reporting it.
        let item = MealItem(group: .other, label: "something fried", grams: 150)
        let total = Nutrition.total(in: [item], foods: table())

        #expect(total.nutrients.kcal == 0)
        #expect(total.unresolvedGrams == 150)
        #expect(!total.isComplete)
        #expect(total.coverage == 0)
    }

    @Test("An unweighed item never reaches the food table")
    func portionsStillScoreOnTheGroup() {
        // A meal logged before grams has no weight to multiply, so the food
        // table has nothing to say and must not guess.
        let old = MealItem(group: .refinedGrains, portion: .large, label: "spaghetti")
        #expect(Protein.grams(in: [old], foods: table()) == Protein.grams(in: [old]))

        // Energy still resolves, via the serving weight the MEDAS scorer already
        // uses: two servings of refined grains is 300 g, and the group row is a
        // rice figure. A meal from before weights is coarse, not absent.
        let total = Nutrition.total(in: [old], foods: table())
        #expect(total.nutrients.kcal == 390)
    }

    @Test("The group has to agree, or the row is not used")
    func groupGuardsTheMatch() {
        // "cream" exists in the table under `dairy`. Filed as `butter` it must
        // not pick that row up — this is the guard that makes exact matching
        // safe without any similarity scoring.
        let wrong = MealItem(group: .butter, label: "cream", grams: 100)
        #expect(table().nutrients(in: wrong) == nil)

        let right = MealItem(group: .dairy, label: "cream", grams: 100)
        #expect(table().nutrients(in: right)?.protein == 2.1)
        #expect(table().nutrients(in: right)?.kcal == 340)
    }

    @Test("A gloss in brackets is dropped; an adjective never is")
    func labelCandidates() {
        #expect(FoodLabel.candidates(for: "Mentaiko (pollock roe)").contains("mentaiko"))
        #expect(FoodLabel.normalised("  Cream Cheese! ") == "cream cheese")
        // "fried chicken" and "chicken" are different foods and the real table
        // holds both, so nothing may strip the adjective to force a match.
        #expect(!FoodLabel.candidates(for: "fried chicken").contains("chicken"))
    }

    @Test("Salt is sodium times a definition, in both directions")
    func saltIsDerivedNotStored() {
        // 2.2 g of sodium in 100 g of mentaiko is 5.6 g of salt equivalent, and
        // nothing stores the second figure — a table carrying both could
        // disagree with itself.
        let mentaiko = MealItem(group: .fish, label: "mentaiko", grams: 100)
        let salt = Nutrition.total(in: [mentaiko], foods: table()).nutrients.saltGrams
        #expect(abs(salt - 5.59) < 0.01)
    }

    @Test("The shipped table resolves the meals that motivated it")
    func shippedTableIsLoadable() throws {
        let url = try #require(Bundle.module.url(forResource: "shaman-config", withExtension: "json"))
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
        let foods = try #require(config.nutrientsPerGram, "run scripts/build-food-table.py")
        #expect(foods.version.contains("sr-legacy"))
        #expect(foods.version.contains("mext"))

        // The mentaiko plate: 200 g pasta + 35 g roe derived 12.1 g of protein
        // against a measured 21 g, and the pasta row was doing the damage.
        let plate = [
            MealItem(group: .refinedGrains, label: "spaghetti", grams: 200),
            MealItem(group: .fish, label: "mentaiko", grams: 35)
        ]
        let derived = Protein.grams(in: plate, foods: foods)
        #expect(derived > 17 && derived < 21, "got \(derived)")

        // Every shipped row names the source row it came from, so a figure that
        // looks wrong can be traced rather than argued about, and every figure
        // is inside what a food can physically be per 100 g.
        for (key, food) in foods.foods.merging(foods.groups, uniquingKeysWith: { a, _ in a }) {
            #expect(food.source.contains(":"), "\(key) has no source row")
            let per100g = food.per100g
            #expect(per100g.protein >= 0 && per100g.protein <= 100, "\(key) protein")
            #expect(per100g.fat >= 0 && per100g.fat <= 100, "\(key) fat")
            #expect(per100g.carbohydrate >= 0 && per100g.carbohydrate <= 100, "\(key) carbohydrate")
            // Pure fat is 884 kcal per 100 g and nothing on a plate exceeds it.
            #expect(per100g.kcal >= 0 && per100g.kcal <= 900, "\(key) is \(per100g.kcal) kcal")
        }
    }

    @Test("Every food group answers, except the one that must not")
    func everyGroupHasARepresentative() throws {
        let url = try #require(Bundle.module.url(forResource: "shaman-config", withExtension: "json"))
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
        let foods = try #require(config.nutrientsPerGram)

        // This is what makes a daily energy figure honest rather than partial:
        // any group a model can name resolves to something sourced.
        for group in FoodGroup.allCases where group != .other {
            #expect(foods.representative(of: group) != nil, "\(group.rawValue) has no fallback")
        }
        #expect(foods.representative(of: .other) == nil, "`other` must stay unanswerable")

        // Every key in the shipped table is a real group. `potatoes|potatoes`
        // shipped once and could never match anything, being filed under a food
        // group that does not exist.
        let known = Set(FoodGroup.allCases.map(\.rawValue))
        for key in foods.foods.keys {
            let group = String(key.split(separator: "|")[0])
            #expect(known.contains(group), "\(key) is filed under no FoodGroup")
        }
    }
}
