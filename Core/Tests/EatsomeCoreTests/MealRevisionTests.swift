import Foundation
import Testing
@testable import EatsomeCore

@Suite("Corrections")
struct MealRevisionTests {
    static let composition = Nutrients(protein: 4.5, fat: 3.2, carbohydrate: 12.1, kcal: 95, sodium: 210)
    static let fried = Nutrients(protein: 25, fat: 14, carbohydrate: 8, kcal: 260, sodium: 500)
    static let seven = #"{"protein":25,"fat":14,"carbohydrate":8,"kcal":260,"sodium_mg":500,"alcohol":0,"caffeine_mg":0}"#
    static let five = #"{"protein":25,"fat":14,"carbohydrate":8,"kcal":260,"sodium_mg":500}"#

    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    static func meal() -> MealEntry {
        MealEntry(
            eatenAt: 0,
            dishes: [
                MealDish(name: "chicken plate", count: 1, items: [
                    MealItem(
                        label: "chicken", grams: 150, per100g: composition,
                        alternatives: [FoodAlternative(label: "turkey", per100g: composition, grams: 210)],
                        brand: "Nando's",
                        sizes: [FoodSize(label: "half", grams: 300, per100g: composition)]
                    ),
                    MealItem(label: "rice", grams: 200, per100g: composition),
                ]),
                MealDish(name: "beer", count: 1, items: [
                    MealItem(label: "lager", grams: 500, per100g: composition),
                ]),
            ],
            source: .text
        )
    }

    // MARK: Meals

    @Test("A revised row restates its composition and is stamped user")
    func reviseRestates() throws {
        let revision = try Self.decode(MealRevision.self, #"{"add":[],"revise":[{"index":1,"label":"fried chicken","grams":150,"per_100g":\#(Self.seven),"preparation":["deep_fried"]}],"dish_counts":[],"dish_names":[],"remove":[],"notes":null}"#)
        let original = Self.meal()
        let corrected = revision.applied(to: original)
        let row = try #require(corrected.items.first)
        #expect(row.label == "fried chicken")
        #expect(row.per100g == Self.fried)
        #expect(row.preparation == [.deepFried])
        #expect(row.provenance == .user)
        // The rename retires the shortlist and the old product's sizes; the
        // brand is the same chain.
        #expect(row.alternatives.isEmpty)
        #expect(row.sizes.isEmpty)
        #expect(row.brand == "Nando's")
        #expect(corrected.wasCorrected)
        // The untouched rows are exactly as they were.
        #expect(corrected.items[1] == original.items[1])
        #expect(corrected.id == original.id)
        #expect(revision.summary == "1 changed")
    }

    @Test("A weight-only change keeps the shortlist and the sizes")
    func weightOnly() throws {
        let revision = MealRevision(revise: [.init(index: 1, label: "chicken", grams: 220, per100g: Self.composition)])
        let row = try #require(revision.applied(to: Self.meal()).items.first)
        #expect(row.grams == 220)
        #expect(row.alternatives.count == 1)
        #expect(row.sizes.count == 1)
        #expect(row.provenance == .user)
    }

    @Test("A revision without composition does not decode")
    func requiresComposition() {
        #expect(throws: (any Error).self) {
            try Self.decode(MealRevision.self, #"{"add":[],"revise":[{"index":1,"label":"fried chicken","grams":150,"preparation":[]}],"dish_counts":[],"dish_names":[],"remove":[],"notes":null}"#)
        }
        // Five figures is the old contract; seven or nothing.
        #expect(throws: (any Error).self) {
            try Self.decode(MealRevision.self, #"{"add":[{"label":"butter","grams":10,"per_100g":\#(Self.five),"preparation":[],"alternatives":[]}],"revise":[],"dish_counts":[],"dish_names":[],"remove":[],"notes":null}"#)
        }
    }

    @Test("Added rows land in one unnamed dish, stamped user; removals and bad indices are safe")
    func addRemove() throws {
        let revision = MealRevision(
            add: [.init(label: "butter", grams: 10, per100g: Self.composition)],
            remove: [3, 99, 0]
        )
        let corrected = revision.applied(to: Self.meal())
        #expect(corrected.dishes.count == 2) // beer dish gone (its only item removed), unnamed dish added
        #expect(corrected.dishes.last?.name == nil)
        #expect(corrected.dishes.last?.items.first?.label == "butter")
        #expect(corrected.dishes.last?.items.first?.provenance == .user)
        #expect(!corrected.items.contains { $0.label == "lager" })
        #expect(corrected.items.count == 3)
    }

    @Test("An added row's rivals arrive priced and weighed, without an id, and become alternatives")
    func addedRowRivals() throws {
        let revision = try Self.decode(MealRevision.self, #"{"add":[{"label":"butter","grams":10,"per_100g":\#(Self.seven),"preparation":[],"alternatives":[{"label":"margarine","grams":10,"per_100g":\#(Self.seven)}]}],"revise":[],"dish_counts":[],"dish_names":[],"remove":[],"notes":null}"#)
        let corrected = revision.applied(to: Self.meal())
        let butter = try #require(corrected.items.last)
        #expect(butter.label == "butter")
        #expect(butter.alternatives.map(\.label) == ["margarine"])
        #expect(butter.alternatives.first?.grams == 10)
        #expect(butter.alternatives.first?.per100g == Self.fried)
    }

    @Test("Two rows sharing an id do not trap the dish rebuild")
    func duplicateIDs() {
        var meal = Self.meal()
        let twin = meal.dishes[0].items[0]
        meal.dishes[1].items.append(twin)
        let revision = MealRevision(revise: [.init(index: 1, label: "chicken", grams: 1, per100g: Self.composition)])
        _ = revision.applied(to: meal)
    }
}
