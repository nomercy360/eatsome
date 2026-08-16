import Foundation
import Testing

@testable import EatsomeCore

@Suite("Composition and the self-check")
struct NutrientsTests {
    /// The bug this rewrite exists partly to fix. Ethanol is 7 kcal/g and its
    /// energy has always been inside `kcal`; with no column for it, the Atwater
    /// check could not reconcile anything alcoholic and reported a correct
    /// composition as a broken one.
    @Test("A beer reconciles now, and would not have before")
    func alcoholClosesAtwater() {
        // A pint of ordinary lager, per 100 ml: ~4 g ethanol, ~3 g carbohydrate,
        // ~43 kcal — of which ethanol is ~28 and carbohydrate ~12.
        let lager = Nutrients(carbohydrate: 3, kcal: 43, alcohol: 4)

        let delta = try? #require(lager.atwaterDelta)
        #expect(lager.failsAtwater == false)
        #expect((delta ?? 1) < Nutrients.atwaterTolerance)

        // The same figures with the alcohol column removed — which is exactly
        // what the previous schema could represent — fail by a mile.
        let withoutColumn = Nutrients(carbohydrate: 3, kcal: 43)
        #expect(withoutColumn.failsAtwater)
        #expect((withoutColumn.atwaterDelta ?? 0) > 0.6)
    }

    @Test("A composition that disagrees with itself is caught")
    func badCompositionFails() {
        let honest = Nutrients(protein: 20, fat: 10, carbohydrate: 30, kcal: 290)
        #expect(honest.failsAtwater == false)

        var wrong = honest
        wrong.kcal = 600
        #expect(wrong.failsAtwater)
    }

    @Test("No energy is an absence, not a disagreement")
    func zeroEnergyIsNotChecked() {
        let water = Nutrients(sodium: 4)
        #expect(water.atwaterDelta == nil)
        #expect(water.failsAtwater == false)
    }

    @Test("Salt is derived from sodium, once")
    func saltFromSodium() {
        let value = Nutrients(sodium: 1000)
        #expect(abs(value.saltGrams - 2.542) < 0.01)
    }

    /// Caffeine used to live on the printed panel, so a filter coffee — the
    /// most common caffeinated thing anybody logs — had none unless a label
    /// happened to be in the photograph. As composition it scales with weight
    /// and sums like everything else.
    @Test("Caffeine scales with weight and sums across a day")
    func caffeineIsComposition() {
        let coffee = Nutrients(kcal: 2, caffeine: 40)   // per 100 ml
        let mug = coffee.forGrams(250)
        #expect(abs(mug.caffeine - 100) < 0.001)

        let twoMugs = mug + mug
        #expect(abs(twoMugs.caffeine - 200) < 0.001)
        // And it is not energy.
        #expect(mug.atwaterEnergy == 0)
    }

    @Test("Weight is the multiplier and nothing else is")
    func gramsAreAbsolute() {
        let item = MealItem(
            label: "grilled chicken",
            grams: 250,
            per100g: Nutrients(protein: 31, fat: 3.6, carbohydrate: 0, kcal: 165)
        )
        #expect(abs(item.nutrients.protein - 77.5) < 0.001)
        #expect(abs(item.nutrients.kcal - 412.5) < 0.001)
    }

    /// The old `count × size × portion` product is what made one bowl of ramen
    /// worth 126 g of protein. Changing the count rewrites the weights.
    @Test("Changing the count rewrites the weights rather than scaling later")
    func countRewritesWeights() {
        let dish = MealDish(
            name: "SAVAS milk protein",
            count: 1,
            items: [
                MealItem(label: "milk protein drink", grams: 200, per100g: Nutrients(protein: 7.5, kcal: 51.5))
            ]
        )
        let four = dish.scaled(toCount: 4)
        #expect(four.count == 4)
        #expect(abs(four.grams - 800) < 0.001)
        #expect(abs(four.nutrients.protein - 60) < 0.001)
        // Scaling back is exact, not lossy.
        #expect(abs(four.scaled(toCount: 1).grams - 200) < 0.001)
    }

    /// The shortlist has to move with the food it is a shortlist for.
    ///
    /// It used to stay anchored to the count at recognition while the item
    /// moved to the count now, so picking a rival after touching the stepper
    /// replaced two servings with one serving's worth of the rival — and
    /// nothing on screen said so.
    ///
    /// `sizes` is the deliberate exception in the same function: a published
    /// size is one serving of the chain's product and is multiplied by the
    /// count where it is used, so scaling it here as well would square it.
    @Test("Rivals scale with the count; published sizes do not")
    func shortlistFollowsTheCount() {
        let composition = Nutrients(protein: 12, fat: 8, carbohydrate: 24, kcal: 220)
        let dish = MealDish(
            name: "Italian B.M.T.",
            count: 1,
            items: [
                MealItem(
                    label: "italian b.m.t., 6-inch",
                    grams: 229,
                    per100g: composition,
                    alternatives: [
                        FoodAlternative(label: "roast beef", per100g: composition, grams: 240)
                    ],
                    brand: "Subway",
                    sizes: [
                        FoodSize(label: "6-inch", grams: 229, per100g: composition),
                        FoodSize(label: "Footlong", grams: 458, per100g: composition)
                    ]
                )
            ]
        )

        let two = dish.scaled(toCount: 2)
        let item = try? #require(two.items.first)
        #expect(item?.grams == 458)
        #expect(item?.alternatives.first?.grams == 480)
        // Published sizes are untouched: still one serving each.
        #expect(item?.sizes.map(\.grams) == [229, 458])

        // And it round-trips, so the stepper is reversible.
        let back = two.scaled(toCount: 1)
        #expect(back.items.first?.grams == 229)
        #expect(back.items.first?.alternatives.first?.grams == 240)
    }

    @Test("A partial panel substitutes figure by figure")
    func panelSubstitutesPerFigure() {
        let dish = MealDish(
            name: "protein bar",
            panel: NutritionPanel(kcal: 200, protein: 20),
            items: [
                MealItem(label: "protein bar", grams: 60, per100g: Nutrients(protein: 10, fat: 8, carbohydrate: 30, kcal: 400, sodium: 200))
            ]
        )
        // Panel wins where it printed something…
        #expect(dish.nutrients.kcal == 200)
        #expect(dish.nutrients.protein == 20)
        // …and the model's figures survive where it did not.
        #expect(abs(dish.nutrients.fat - 4.8) < 0.001)
        #expect(abs(dish.nutrients.sodium - 120) < 0.001)

        let sources = try? #require(dish.panelSources)
        #expect(sources?.kcal == .panel)
        #expect(sources?.protein == .panel)
        #expect(sources?.fat == .model)
    }
}

@Suite("What the wire turns into")
struct RecognitionConversionTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    private static let comp = #"{"protein":10,"fat":5,"carbohydrate":20,"kcal":165,"sodium_mg":300,"alcohol":0,"caffeine_mg":0}"#

    /// A rival is rarely the same size as the first answer. Dropping its weight
    /// prices a tuna sub by what the turkey sub weighed — a figure that looks
    /// chosen and is not — so the weight crosses from the wire with the rest.
    @Test("A rival brings its own weight across, not just its composition")
    func alternativeCarriesWeight() throws {
        let json = #"{"label":"tuna sub","per_100g":\#(Self.comp),"grams":238}"#
        let stored = try decode(RecognizedAlternative.self, json).stored
        #expect(stored.grams == 238)
        #expect(stored.label == "tuna sub")
    }

    /// `carbohydrate: 1` is true per 100 ml of a Monster and wrong by 3.55× for
    /// the can. With the net printed that is arithmetic; without it there is
    /// nothing honest to file against the container.
    @Test("A per-100 panel is scaled by the printed net, or refused")
    func panelScalesOnlyWhenItCan() throws {
        func panel(_ extra: String) throws -> NutritionPanel? {
            try decode(RecognizedPanel.self, #"""
            {"protein":1,"calories":47,"fat":0,"carbohydrate":11,"salt":null,"sodium":null,
             "alcohol":null,"caffeine":32,\#(extra)}
            """#).stored
        }

        let scaled = try #require(try panel(#""basis":"per_100ml","net_ml":355,"net_g":null"#))
        #expect(abs((scaled.kcal ?? 0) - 166.85) < 0.01)
        #expect(abs((scaled.caffeine ?? 0) - 113.6) < 0.01)

        // No net printed: there is no factor, so nothing is filed.
        #expect(try panel(#""basis":"per_100ml","net_ml":null,"net_g":null"#) == nil)

        // Already about the container: taken as printed.
        let asIs = try #require(try panel(#""basis":"per_container","net_ml":null,"net_g":null"#))
        #expect(asIs.kcal == 47)
    }
}
