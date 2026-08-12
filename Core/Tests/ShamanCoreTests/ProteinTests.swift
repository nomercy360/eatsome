import Foundation
import Testing
@testable import ShamanCore

@Suite("Nutrient totals")
struct ProteinTests {
    private var foods: FoodNutrientTable {
        FoodNutrientTable(
            version: "test",
            foods: [
                "fish|salmon": .init(
                    per100g: Nutrients(protein: 20, fat: 8, kcal: 160, sodium: 50),
                    source: "sr:salmon", basis: "analysed", name: "Salmon"
                ),
                "beef|beef": .init(
                    per100g: Nutrients(protein: 24, fat: 10, kcal: 200, sodium: 40),
                    source: "sr:beef", basis: "analysed", name: "Beef"
                ),
                "rice|rice": .init(
                    per100g: Nutrients(protein: 2, carbohydrate: 28, kcal: 130, sodium: 1),
                    source: "sr:rice", basis: "analysed", name: "Rice, cooked"
                )
            ]
        )
    }

    @Test("Named, weighed foods sum from composition rows")
    func sumsAcrossItems() {
        let items = [
            MealItem(kind: .beef, label: "beef", grams: 300),
            MealItem(kind: .rice, label: "rice", grams: 400)
        ]
        #expect(Protein.grams(in: items, foods: foods) == 80)
        #expect(Nutrition.total(in: items, foods: foods).exactGrams == 700)
    }

    @Test("Meal share scales nutrients and resolution coverage")
    func sharedPlate() {
        var shared = MealEntry(
            eatenAt: 0,
            items: [MealItem(kind: .fish, label: "salmon", grams: 200)],
            source: .photo
        )
        shared.share = .part
        let total = Nutrition.total(in: shared, foods: foods)
        #expect(total.nutrients.protein == 20)
        #expect(total.exactGrams == 100)

        shared.share = .taste
        #expect(Nutrition.total(in: shared, foods: foods).nutrients.protein == 10)
    }

    @Test("Dish size and count never multiply absolute grams")
    func gramsAreAbsolute() {
        let pan = MealDish(
            name: "beef rice",
            count: 3,
            size: .large,
            items: [
                MealItem(kind: .beef, label: "beef", grams: 300),
                MealItem(kind: .rice, label: "rice", grams: 400)
            ]
        )
        #expect(pan.weighed)
        #expect(Protein.grams(in: pan, foods: foods) == 80)
        #expect(Protein.grams(in: pan.flattened(), foods: foods) == 80)
    }

    @Test("Changing a counted dish rewrites weight instead of stacking factors")
    func countScalesGrams() {
        let beers = MealDish(
            name: "beer",
            count: 3,
            items: [MealItem(kind: .beer, label: "beer", grams: 1500)]
        )
        #expect(beers.scaled(toCount: 1).items[0].grams == 500)
        #expect(beers.scaled(toCount: 6).items[0].grams == 3000)
    }

    @Test("Grams outrank legacy portion arithmetic")
    func gramsWinOverPortion() throws {
        let weighed = MealItem(kind: .fish, portion: .small, grams: 200)
        #expect(weighed.effectiveServings() == 2)

        let legacy = try JSONDecoder().decode(
            MealItem.self,
            from: Data(#"{"id":"\#(UUID().uuidString)","group":"fish","portion":"large"}"#.utf8)
        )
        #expect(legacy.grams == nil)
        #expect(legacy.kind == .fish)
        #expect(legacy.effectiveServings() == 2)
    }

    @Test("A printed panel wins and settles the whole packaged dish")
    func panelOverridesComposition() {
        let carton = MealDish(
            name: "protein drink",
            count: 2,
            panel: NutritionPanel(protein: 15, calories: 103, sodium: 0.1),
            items: [MealItem(kind: .mealReplacement, label: "protein drink", grams: 500)]
        )
        let total = Nutrition.total(in: carton, foods: foods)
        #expect(total.nutrients.protein == 30)
        #expect(total.nutrients.kcal == 206)
        #expect(total.nutrients.sodium == 200)
        #expect(total.isComplete)
        #expect(!total.saltIsFloor)
    }

    @Test("An unresolved item contributes no invented nutrition")
    func unresolvedStaysVisible() {
        let dip = MealItem(kind: .sauceCondiment, label: "dipping sauce", grams: 40)
        let total = Nutrition.total(in: [dip], foods: foods)
        #expect(total.nutrients == .zero)
        #expect(total.unresolvedGrams == 40)
        #expect(!total.isComplete)
    }

    @Test("Future meal-share values do not erase a meal")
    func shareDecodeFallback() throws {
        let future = try JSONDecoder().decode(MealShare.self, from: Data(#""nibbled""#.utf8))
        #expect(future == .whole)
        #expect(MealShare.allCases.map(\.chipName) == ["All of it", "Half", "A taste"])
    }
}
