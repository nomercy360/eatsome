import Foundation
import Testing
@testable import EatsomeCore

/// The wire contract, from the phone's side. These fixtures are what
/// `Backend/src/contracts.ts` accepts — the same field names, the same
/// spellings — so a change on either side that the other did not follow fails
/// here rather than on a real meal.
@Suite("MealRecognition")
struct MealRecognitionTests {
    static let composition = """
    {"protein":4.5,"fat":3.2,"carbohydrate":12.1,"kcal":95,"sodium_mg":210,"alcohol":0,"caffeine_mg":0}
    """
    static let lager = """
    {"protein":0.5,"fat":0,"carbohydrate":3.6,"kcal":43,"sodium_mg":4,"alcohol":3.9,"caffeine_mg":0}
    """
    static let ramen = """
    {"name":"ramen","count":1,"panel":null,"ingredients":[{"label":"tonkotsu ramen","grams":450,"per_100g":\(composition),"preparation":["boiled"],"brand":null,"forks":[],"alternatives":[{"label":"shoyu ramen","grams":430,"per_100g":\(composition)}]}]}
    """
    static let beer = """
    {"name":"lager","count":2,"panel":{"protein":0.5,"calories":43,"fat":0,"carbohydrate":3.6,"salt":null,"sodium":4,"alcohol":3.9,"caffeine":null,"basis":"per_100ml","net_ml":700,"net_g":null},"ingredients":[{"label":"lager","grams":700,"per_100g":\(lager),"preparation":[],"brand":"Asahi","forks":[{"axis":"size","chosen_from":"assumed","options":[{"label":"350 ml can","grams":700,"per_100g":\(lager),"basis":"published","chosen":true},{"label":"500 ml can","grams":1000,"per_100g":\(lager),"basis":"published","chosen":false}]}],"alternatives":[]}]}
    """

    static func decode(_ json: String) throws -> MealRecognition {
        try JSONDecoder().decode(MealRecognition.self, from: Data(json.utf8))
    }

    @Test("A Worker answer becomes dishes, items, weighed rivals and forks, all stamped model")
    func fullAnswerBecomesMeal() throws {
        let recognition = try Self.decode(#"{"dishes":[\#(Self.ramen),\#(Self.beer)]}"#)
        #expect(!recognition.isEmpty)
        let meal = try #require(recognition.mealEntry(eatenAt: 1_786_781_100_000, source: .photo, photoHash: "ab" ))
        #expect(meal.dishes.count == 2)
        #expect(meal.source == .photo)
        #expect(meal.photoHash == "ab")
        #expect(!meal.wasCorrected)

        let ramen = try #require(meal.dishes.first?.items.first)
        #expect(ramen.label == "tonkotsu ramen")
        #expect(ramen.grams == 450)
        #expect(ramen.preparation == [.boiled])
        #expect(ramen.brand == nil)
        #expect(ramen.provenance == .model)
        #expect(ramen.alternatives.map(\.label) == ["shoyu ramen"])
        #expect(ramen.alternatives.first?.grams == 430)

        let beer = meal.dishes[1]
        #expect(beer.count == 2)
        let lager = try #require(beer.items.first)
        #expect(lager.brand == "Asahi")
        let fork = try #require(lager.forks.first)
        #expect(fork.axis == "size")
        #expect(fork.chosenFrom == .assumed)
        #expect(fork.chosen?.label == "350 ml can")
        #expect(fork.options.map(\.grams) == [700, 1000])
        // The item's own arithmetic: 700 g × 43 kcal / 100 g.
        #expect(abs(lager.nutrients.kcal - 301) < 0.01)
        #expect(abs(lager.nutrients.alcohol - 27.3) < 0.01)
        // The panel was per 100 ml of a 700 ml net; scaled once at ingest and
        // substituted figure by figure, so the dish reads the printed number.
        #expect(abs(beer.nutrients.kcal - 301) < 0.01)
        #expect(beer.panelSources?.kcal == .panel)
    }

    @Test("Nothing found is an empty list and no meal, not a meal worth nothing")
    func emptyIsNoMeal() throws {
        let recognition = try Self.decode(#"{"dishes":[]}"#)
        #expect(recognition.isEmpty)
        #expect(recognition.mealEntry(eatenAt: 0, source: .text) == nil)
    }

    @Test("An empty brand is no brand")
    func emptyBrandIsNil() throws {
        let json = Self.ramen.replacingOccurrences(of: #""brand":null"#, with: #""brand":"""#)
        let meal = try #require(try Self.decode(#"{"dishes":[\#(json)]}"#).mealEntry(eatenAt: 0, source: .text))
        #expect(meal.items.first?.brand == nil)
    }

    @Test("A rival without a weight, or an ingredient without composition, does not decode")
    func wireRequiresWeightAndComposition() {
        let unweighed = Self.ramen.replacingOccurrences(of: #""grams":430,"#, with: "")
        #expect(throws: (any Error).self) { try Self.decode(#"{"dishes":[\#(unweighed)]}"#) }
        let unpriced = Self.ramen.replacingOccurrences(of: #""per_100g":\#(Self.composition),"preparation""#, with: #""preparation""#)
        #expect(throws: (any Error).self) { try Self.decode(#"{"dishes":[\#(unpriced)]}"#) }
    }
}
