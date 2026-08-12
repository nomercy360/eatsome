import Foundation
import Testing
@testable import ShamanCore

@Suite("Nutrients from named foods")
struct FoodNutrientTableTests {
    private func row(
        protein: Double,
        kcal: Double,
        source: String,
        name: String
    ) -> FoodNutrientTable.Food {
        .init(
            per100g: Nutrients(protein: protein, carbohydrate: 10, kcal: kcal, sodium: 10),
            source: source,
            basis: "analysed",
            name: name
        )
    }

    private func table() -> FoodNutrientTable {
        FoodNutrientTable(
            version: "test",
            groups: [
                "sauce_condiment": row(
                    protein: 2, kcal: 80, source: "sr:generic-sauce", name: "Generic sauce"
                )
            ],
            foods: [
                "pasta_noodles|spaghetti": row(
                    protein: 5.8, kcal: 158, source: "sr:169737", name: "Pasta, cooked"
                ),
                "sauce_condiment|soy sauce": row(
                    protein: 8.1, kcal: 53, source: "sr:174277", name: "Soy sauce"
                ),
                "beef|grilled beef": row(
                    protein: 27, kcal: 220, source: "sr:168731", name: "Beef, grilled"
                ),
                "cream|cream": row(
                    protein: 2.1, kcal: 340, source: "sr:170859", name: "Cream, fluid"
                )
            ]
        )
    }

    @Test("A named food resolves every nutrient from one source row")
    func namedFoodWins() {
        let item = MealItem(kind: .pastaNoodles, label: "spaghetti", grams: 200)
        let total = Nutrition.total(in: [item], foods: table())

        #expect(total.nutrients.protein == 11.6)
        #expect(total.nutrients.kcal == 316)
        #expect(total.exactGrams == 200)
        #expect(total.isComplete)
    }

    @Test("The kind guards exact label matching")
    func kindGuardsTheMatch() {
        let wrong = MealItem(kind: .butterMargarine, label: "cream", grams: 100)
        #expect(table().nutrients(in: wrong) == nil)

        let right = MealItem(kind: .cream, label: "cream", grams: 100)
        #expect(table().nutrients(in: right)?.protein == 2.1)
    }

    @Test("A generic dipping sauce stays unresolved")
    func genericSauceIsHonest() {
        let dip = MealItem(kind: .sauceCondiment, label: "dipping sauce", grams: 40)
        let total = Nutrition.total(in: [dip], foods: table())

        #expect(total.nutrients == .zero)
        #expect(total.unresolvedGrams == 40)
        #expect(total.coverage == 0)
        #expect(!total.isComplete)
    }

    @Test("A composition hint can deterministically resolve a generic sauce")
    func soyHintResolvesSauce() {
        let dip = MealItem(
            kind: .sauceCondiment,
            label: "dipping sauce",
            compositionHints: [.soyBased],
            grams: 40
        )
        let resolved = table().resolving(dip)
        let total = Nutrition.total(in: [resolved], foods: table())

        #expect(resolved.resolution?.status == .exact)
        #expect(resolved.resolution?.foodRef?.id == "174277")
        #expect(total.exactGrams == 40)
        #expect(total.unresolvedGrams == 0)
    }

    @Test("A broad representative is opt-in and remains visibly estimated")
    func representativeRequiresProvenance() {
        let dip = MealItem(kind: .sauceCondiment, label: "mystery sauce", grams: 40)
        var estimated = dip
        estimated.resolution = NutrientResolution(status: .classEstimate)

        #expect(Nutrition.total(in: [dip], foods: table()).unresolvedGrams == 40)
        let total = Nutrition.total(in: [estimated], foods: table())
        #expect(total.estimatedGrams == 40)
        #expect(total.exactGrams == 0)
        #expect(!total.isComplete)
    }

    @Test("Preparation can choose a deterministic composition row")
    func preparationResolvesBeef() {
        let beef = MealItem(kind: .beef, label: "beef", preparation: [.grilled], grams: 100)
        #expect(table().food(for: beef)?.source == "sr:168731")
    }

    @Test("Legacy group JSON decodes, while new JSON writes kind only")
    func transitionBridge() throws {
        let id = UUID().uuidString
        let old = Data(#"{"id":"\#(id)","group":"cooked_tomato_sauce","portion":"medium","label":"tomato sauce","grams":40}"#.utf8)
        let item = try JSONDecoder().decode(MealItem.self, from: old)
        #expect(item.kind == .sauceCondiment)

        let written = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        #expect(written.contains("\"kind\":\"sauce_condiment\""))
        #expect(!written.contains("\"group\""))
    }

    @Test("The shipped table uses only current kinds and carries provenance")
    func shippedTableIsLoadable() throws {
        let url = try #require(Bundle.module.url(forResource: "shaman-config", withExtension: "json"))
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
        let foods = try #require(config.nutrientsPerGram, "run scripts/build-food-table.py")
        let current = Set(FoodKind.allCases.map(\.rawValue))

        for (key, food) in foods.foods.merging(foods.groups, uniquingKeysWith: { first, _ in first }) {
            let kind = String(key.split(separator: "|")[0])
            #expect(current.contains(kind), "\(key) is filed under no FoodKind")
            #expect(food.source.contains(":"), "\(key) has no source row")
            #expect(food.per100g.kcal >= 0 && food.per100g.kcal <= 900)
        }

        #expect(foods.food(for: "soy sauce", kind: .sauceCondiment) != nil)
        #expect(foods.food(for: "grilled beef", kind: .beef) != nil)
        #expect(foods.food(for: "mashed potatoes", kind: .potato) != nil)
        #expect(foods.food(for: "dipping sauce", kind: .sauceCondiment) == nil)
    }

    @Test("Label normalisation never strips meaningful adjectives")
    func labelCandidates() {
        #expect(FoodLabel.candidates(for: "Mentaiko (pollock roe)").contains("mentaiko"))
        #expect(FoodLabel.normalised("  Cream Cheese! ") == "cream cheese")
        #expect(!FoodLabel.candidates(for: "fried chicken").contains("chicken"))
    }
}
