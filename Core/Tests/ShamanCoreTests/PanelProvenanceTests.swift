import Foundation
import Testing

@testable import ShamanCore

/// Where a figure came from, once a panel is involved.
///
/// The branded-food lookup that used to write `published` here is gone:
/// recognition is grounded in search, and a grounded answer arrives with no URL
/// — Gemini returns no grounding metadata beside a response schema — so a
/// chain's figure is a very good `model` figure and the app says so. What is
/// left is the case that was always true: a panel read off the packaging in the
/// photograph settles the figures it prints and nothing else.
@Suite("Panel provenance")
struct PublishedFiguresTests {
    private let composition = Nutrients(
        protein: 12, fat: 14, carbohydrate: 21, kcal: 258, sodium: 480
    )

    private func recognition(panel: NutritionPanel?) -> MealRecognition {
        MealRecognition(dishes: [
            MealRecognition.Dish(
                name: "Big Mac",
                count: 1,
                panel: panel,
                ingredients: [
                    MealRecognition.Item(label: "big mac", grams: 219, per100g: composition)
                ]
            )
        ])
    }

    @Test("A printed panel settles the figures it prints, and only those")
    func printedPanelMarksWhatItSettled() throws {
        let panel = NutritionPanel(protein: 26, calories: 524, basis: "per_container")
        let dish = try #require(recognition(panel: panel).asMealDishes().first)
        let item = try #require(dish.items.first)

        #expect(item.provenance.kcal == .panel)
        #expect(item.provenance.protein == .panel)
        // Nothing was printed about fat, so the model's figure stands and says so.
        #expect(item.provenance.fat == .model)
        #expect(item.sourceRef == nil)
        // The panel substitutes for the dish; the food underneath is untouched.
        #expect(item.grams == 219)
        #expect(dish.nutrients.kcal == 524)
    }

    @Test("An empty panel settles nothing")
    func emptyPanelIsDropped() throws {
        let dish = try #require(recognition(panel: NutritionPanel()).asMealDishes().first)
        #expect(dish.panel == nil)
        #expect(try #require(dish.items.first).provenance == .model)
    }

    @Test("A grounded figure for a chain's product is still the model's")
    func groundedIsStillModel() throws {
        // The honest half of enabling search. The numbers got much better —
        // a Subway JP footlong went from 845 kcal to 699 against a published
        // 698 — and not one of them arrives with a source, so none of them may
        // wear a label that claims one.
        let dish = try #require(recognition(panel: nil).asMealDishes().first)
        let item = try #require(dish.items.first)
        #expect(item.provenance == .model)
        #expect(item.sourceRef == nil)
        #expect(!item.provenance.isEntirelyRead)
    }

    @Test("A correction takes the figure back off whatever set it")
    func choosingAnAlternativeDropsTheCitation() throws {
        // `choosing` re-prices the row from the alternative's own composition,
        // so whatever settled the old figure no longer settles anything.
        var item = MealItem(
            label: "big mac",
            grams: 219,
            per100g: composition,
            provenance: .all(.panel),
            sourceRef: SourceRef(url: "https://example.com/x", fetchedAt: 1),
            alternatives: [FoodAlternative(label: "quarter pounder", per100g: composition)]
        )
        item = item.choosing(try #require(item.alternatives.first))

        #expect(item.sourceRef == nil)
        #expect(item.provenance == .model)
    }
}
