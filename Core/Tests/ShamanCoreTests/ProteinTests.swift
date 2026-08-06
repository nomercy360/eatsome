import Foundation
import Testing
@testable import ShamanCore

@Suite("Protein")
struct ProteinTests {
    @Test("A meal sums its groups by portion")
    func sumsAcrossItems() {
        let dinner = MealEntry.fixture(daysAgo: 0, [
            (.fish, .large),       // 22 × 2
            (.wholeGrains, .medium), // 4 × 1
            (.vegetables, .small)   // 2 × 0.5
        ])
        #expect(Protein.grams(in: dinner) == 44 + 4 + 1)
    }

    @Test("Eating half the plate is half the protein")
    func sharedPlate() {
        var shared = MealEntry.fixture(daysAgo: 0, [(.whiteMeat, .medium)])
        shared.share = .part
        #expect(Protein.grams(in: shared) == 13)
    }

    @Test("The MEDAS per-meal cap does not apply to protein")
    func capIsForScoringOnly() {
        // Four fillets on one platter score as one plate of fish, but you still
        // ate four fillets' worth of protein.
        let platter = MealEntry.fixture(
            daysAgo: 0,
            Array(repeating: (FoodGroup.fish, Portion.medium), count: 4)
        )
        #expect(platter.servings(of: .fish) == MealScoring.perMealGroupCap)
        #expect(Protein.grams(in: platter) == 88)
    }

    @Test("A described dish is counted whole, with no share taken off it")
    func dishIsOneServingOfItself() {
        // The dishes screen counts a recipe as written. Halving belongs to the
        // meal you log from it, which is where `share` lives.
        let soup: [MealItem] = [
            MealItem(group: .legumes, portion: .large),   // 8 × 2
            MealItem(group: .vegetables, portion: .medium) // 2 × 1
        ]
        #expect(Protein.grams(in: soup) == 18)

        var half = MealEntry.fixture(daysAgo: 0, [(.legumes, .large), (.vegetables, .medium)])
        half.share = .part
        #expect(Protein.grams(in: half) == 9)
    }

    @Test("A counted dish contributes its count, not its portion")
    func countedDish() {
        // Three beers arrive as one dish with count 3, flattened to servings 3.0.
        // No case of `Portion` can say three, which is why the field exists.
        let beers = MealItem(group: .alcohol, portion: .medium, label: "beer", dish: "beer", servings: 3)
        #expect(beers.effectiveServings() == 3)

        // A meal from before dishes has no servings and is unchanged by any of this.
        let legacy = MealItem(group: .fish, portion: .large)
        #expect(legacy.effectiveServings() == Portion.large.servings)

        let dinner = MealEntry(
            eatenAt: 0,
            items: [
                MealItem(group: .whiteMeat, portion: .medium, dish: "fried rice", servings: 2),
                MealItem(group: .refinedGrains, portion: .medium, dish: "fried rice", servings: 2)
            ],
            source: .photo
        )
        // 26 × 2 for the meat, 3 × 2 for the rice.
        #expect(Protein.grams(in: dinner) == 52 + 6)
    }

    @Test("A dish is worth the same whether it is read whole or as rows")
    func dishAgreesWithItsRows() {
        // The dish sheet reads the dish; the sentence above it reads the rows
        // `flattened()` produced. A tester saw 38 g on one and 76 g on the
        // other because only one of them applied `size` (TestFlight, build on
        // 2026-08-06). The two must not be able to drift again.
        for size in Portion.allCases {
            for count in [1, 2, 5] {
                let ramen = MealDish(
                    name: "ramen",
                    count: count,
                    size: size,
                    items: [
                        MealItem(group: .refinedGrains, portion: .large, label: "ramen noodles"),
                        MealItem(group: .redMeat, portion: .medium, label: "chashu pork"),
                        MealItem(group: .whiteMeat, portion: .medium, label: "soft boiled egg"),
                        MealItem(group: .vegetables, portion: .small, label: "scallions and spinach")
                    ]
                )
                #expect(Protein.grams(in: ramen) == Protein.grams(in: ramen.flattened()))
            }
        }

        // One normal serving is the ingredients as described; a large one is
        // twice that. Reading `dish.items` alone reports the large plate as
        // normal, which is precisely the bug.
        let plate = [MealItem(group: .redMeat, portion: .medium, label: "steak")]
        let large = MealDish(name: "steak", size: .large, items: plate)
        #expect(Protein.grams(in: large) == Protein.grams(in: plate) * 2)
    }

    @Test("A label beats the food group, before saving and after")
    func panelBeatsTheGroupOnBothSides() {
        // A zero-calorie energy drink is `other`, which the table calls 2 g.
        // The can says 0. A tester saw 2 g while composing and 0 g once it was
        // saved, because the composing screen summed `flattened()` rows and a
        // flat row carries no panel (TestFlight, 2026-08-06).
        let monster = MealDish(
            name: "Monster Energy Drink",
            panel: NutritionPanel(protein: 0, calories: 0),
            items: [MealItem(group: .other, portion: .medium, label: "zero-calorie energy drink")]
        )
        #expect(Protein.grams(in: [monster]) == 0)

        let saved = MealEntry(
            eatenAt: 0,
            items: monster.flattened(),
            source: .photo,
            storedDishes: [monster]
        )
        #expect(Protein.grams(in: saved) == Protein.grams(in: [monster]))

        // And the panel keeps winning as the two controls move: count multiplies
        // the printed figure, size does not touch it.
        var three = monster
        three.count = 3
        three.size = .large
        three.panel = NutritionPanel(protein: 5, calories: 0)
        #expect(Protein.grams(in: [three]) == 15)
    }

    @Test("A drink with no protein reads as the caffeine its label printed")
    func caffeineTakesTheSlot() {
        let monster = MealDish(
            name: "Monster Energy Drink",
            panel: NutritionPanel(protein: 0, caffeine: 142),
            items: [MealItem(group: .other, portion: .medium, label: "zero-calorie energy drink")]
        )
        #expect(PlateFigure.forPlate([monster]) == .caffeine(milligrams: 142))
        #expect(PlateFigure.forPlate([monster]).text == "142 mg caffeine")

        // Two cans is twice the caffeine; a "large" can is not, because the
        // printed figure is for what the container holds.
        var two = monster
        two.count = 2
        two.size = .large
        #expect(PlateFigure.forPlate([two]) == .caffeine(milligrams: 284))

        // Half of it is half of it, exactly as protein is.
        #expect(PlateFigure.forPlate([monster], share: .part) == .caffeine(milligrams: 71))

        // Protein wins whenever there is any: caffeine is the fallback, not a
        // second figure competing for the slot.
        let withFood = [monster, MealDish(name: "onigiri", items: [
            MealItem(group: .fish, portion: .small, label: "salmon")
        ])]
        #expect(PlateFigure.forPlate(withFood) == .protein(grams: 11))

        // An unlabelled coffee alongside it would make 142 mg an understatement
        // of the plate, so the figure stays on protein rather than lying.
        let alsoCoffee = [monster, MealDish(name: "coffee", items: [
            MealItem(group: .coffee, portion: .medium, label: "black coffee")
        ])]
        #expect(PlateFigure.forPlate(alsoCoffee) == .protein(grams: 0))

        // No panel anywhere is the ordinary case and never mentions caffeine.
        let ramen = MealDish(name: "ramen", items: [
            MealItem(group: .refinedGrains, portion: .medium, label: "noodles")
        ])
        #expect(PlateFigure.forPlate([ramen]).text == "3 g protein")
    }

    @Test("A taste is a quarter, and an unknown share is not a lost meal")
    func shareHasThreeAnswers() throws {
        #expect(MealShare.whole.factor == 1.0)
        #expect(MealShare.part.factor == 0.5)
        #expect(MealShare.taste.factor == 0.25)
        #expect(MealShare.allCases.map(\.chipName) == ["All of it", "Half", "A taste"])

        let plate = MealEntry.fixture(daysAgo: 0, [(.whiteMeat, .medium)])
        var picked = plate
        picked.share = .taste
        #expect(Protein.grams(in: picked) == 26 * 0.25)

        // A share written by a newer build decodes to `whole` rather than
        // throwing. Throwing would fail the whole `MealEntry`, and a meal that
        // will not decode is a meal that disappears from the projection without
        // saying so.
        let future = try JSONDecoder().decode(MealShare.self, from: Data(#""nibbled""#.utf8))
        #expect(future == .whole)
        let known = try JSONDecoder().decode(MealShare.self, from: Data(#""taste""#.utf8))
        #expect(known == .taste)
    }

    @Test("A weighed dish is its weight, and nothing multiplies it")
    func gramsAreAbsolute() {
        // 300 g of beef in a pan is three servings of red meat. The portion
        // ladder could not say that at all — `large` caps at two — which is why
        // a photograph of exactly this read low all evening.
        let pan = MealDish(
            name: "beef fried rice",
            count: 1,
            size: .large,
            items: [
                MealItem(group: .redMeat, portion: .large, label: "beef", grams: 300),
                MealItem(group: .refinedGrains, portion: .large, label: "rice", grams: 400)
            ]
        )
        #expect(pan.weighed)
        // 300/100 × 24 for the beef, 400/150 × 3 for the rice. `size: .large`
        // is present and must change nothing.
        #expect(Protein.grams(in: pan) == 72 + 8)

        var normal = pan
        normal.size = .medium
        #expect(Protein.grams(in: normal) == Protein.grams(in: pan))

        // The flat rows agree with the dish, as they must — that equality is
        // what the 38-vs-76 bug broke.
        #expect(Protein.grams(in: pan.flattened()) == Protein.grams(in: pan))
        // And no `servings` is written beside the grams, or the two could drift.
        #expect(pan.flattened().allSatisfy { $0.servings == nil && $0.grams != nil })

        // A dish with no weights is unchanged: the ladder still multiplies.
        let described = MealDish(name: "steak", size: .large,
                                 items: [MealItem(group: .redMeat, portion: .medium)])
        #expect(!described.weighed)
        #expect(Protein.grams(in: described) == 48)
    }

    @Test("The count control rewrites the weight instead of multiplying it")
    func countScalesGrams() {
        let beers = MealDish(
            name: "beer", count: 3,
            items: [MealItem(group: .alcohol, portion: .medium, label: "beer", grams: 1500)]
        )
        // Three 500 ml beers. Saying you only had one takes the weight down to
        // one, rather than leaving 1500 g behind a label that says "1".
        let one = beers.scaled(toCount: 1)
        #expect(one.count == 1)
        #expect(one.items[0].grams == 500)
        #expect(beers.scaled(toCount: 6).items[0].grams == 3000)

        // A dish described in portions has no weight to rewrite, so only the
        // count moves and the old arithmetic still applies.
        let described = MealDish(name: "beer", count: 3,
                                 items: [MealItem(group: .alcohol, portion: .medium)])
        #expect(described.scaled(toCount: 1).count == 1)
        #expect(described.scaled(toCount: 1).items[0].grams == nil)
    }

    @Test("Grams outrank the ladder, and a meal without them is untouched")
    func gramsWinOverPortion() {
        let weighed = MealItem(group: .fish, portion: .small, grams: 200)
        #expect(weighed.effectiveServings() == 2)          // 200/100, not 0.5
        let described = MealItem(group: .fish, portion: .small)
        #expect(described.effectiveServings() == 0.5)

        // Every line in the log written before grams existed still decodes and
        // still scores exactly as it did.
        let legacy = try? JSONDecoder().decode(
            MealItem.self,
            from: Data(#"{"id":"\#(UUID().uuidString)","group":"fish","portion":"large"}"#.utf8)
        )
        #expect(legacy?.grams == nil)
        #expect(legacy?.effectiveServings() == 2.0)
    }

    @Test("The daily target follows body weight and intent")
    func target() {
        #expect(Protein.dailyTarget(weightKilograms: 79.4, intent: .building) == 159)
        #expect(Protein.dailyTarget(weightKilograms: 79.4, intent: .active) == 127)
        #expect(Protein.dailyTarget(weightKilograms: 79.4, intent: .maintain) == 95)
        #expect(Protein.Intent.building.gramsPerKilogram == 2.0)
    }

    @Test("Every food group has a value, and the fats have none")
    func tableIsComplete() {
        for group in FoodGroup.allCases {
            #expect(
                Protein.defaultGramsPerServing[group.rawValue] != nil,
                "\(group.rawValue) is missing from the protein table"
            )
        }
        #expect(Protein.defaultGramsPerServing[FoodGroup.oliveOil.rawValue] == 0)
        #expect(Protein.defaultGramsPerServing[FoodGroup.alcohol.rawValue] == 0)
        // `other` is the bucket for food that was not recognised, and a number
        // there is invented rather than estimated. It read 2 g, which is how a
        // black coffee came to be worth 2 g of protein before `coffee` existed.
        #expect(Protein.defaultGramsPerServing[FoodGroup.other.rawValue] == 0)
        #expect(Protein.defaultGramsPerServing[FoodGroup.coffee.rawValue] == 0)
        #expect(Protein.defaultGramsPerServing[FoodGroup.tea.rawValue] == 0)
        // A black coffee is worth nothing, and reads as nothing.
        let coffee = MealDish(name: "black coffee", items: [
            MealItem(group: .coffee, portion: .medium, label: "black coffee")
        ])
        #expect(PlateFigure.forPlate([coffee]).text == "0 g protein")
    }

    @Test("A configured table overrides the compiled one")
    func configurableTable() {
        let meal = MealEntry.fixture(daysAgo: 0, [(.egg, .medium)])
        #expect(Protein.grams(in: meal) == 6)
        #expect(Protein.grams(in: meal, gramsPerServing: ["egg": 13]) == 13)
        #expect(AppConfig.fallback.proteinTable[FoodGroup.egg.rawValue] == 6)
    }

    @Test("A transcribed panel is kept, and nothing totals it")
    func caloriesAreStoredNeverSummed() throws {
        // The rule used to be that a calorie figure could not exist anywhere.
        // It can now be transcribed off a label, because reading a printed fact
        // is not estimating one — but nothing may add them up. Only packaged
        // food carries a label, so a total would be computed from the packaged
        // fraction of a diet while looking exactly like a total.
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ShamanCore")
        let files = FileManager.default
            .enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)

        for file in files {
            let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
            for banned in ["caloriesToday", "totalCalories", "sumCalories", "caloriesPer"] {
                #expect(!text.contains(banned), "\(file.lastPathComponent) aggregates calories")
            }
        }

        // Protein is the one figure with a complete baseline — every meal has
        // an estimate — so a confirmed value improves that total instead of
        // creating a partial one. That is the whole difference.
        let carton = MealDish(
            name: "protein drink",
            count: 2,
            size: .small,
            panel: NutritionPanel(protein: 15, calories: 103),
            items: [MealItem(group: .dairy, portion: .medium, label: "milk protein")]
        )
        #expect(Protein.grams(in: carton) == 30)
        // Size is ignored for a packaged serving; the table would have said 4.
        #expect(Protein.grams(in: MealDish(name: "x", size: .small, items: carton.items)) == 4)
    }
}
