import Foundation
import Testing
@testable import ShamanCore

@Suite("Olives")
struct OliveRatingTests {
    @Test("A plate with nothing on it either way sits at neutral")
    func neutralPlate() {
        // Coffee, eggs and rice all have a weight of zero on purpose.
        let breakfast = MealEntry.fixture(daysAgo: 0, [
            (.coffee, .medium), (.egg, .medium), (.refinedGrains, .medium)
        ])
        let rating = OliveRating.forMeal(breakfast)
        #expect(rating.olives == 3)
        #expect(rating.leading.isEmpty)
        #expect(rating.reason() == "This meal sits in the middle.")
    }

    @Test("Fish, beans, greens and olive oil is as good as it gets")
    func strongestPlate() {
        let dinner = MealEntry.fixture(daysAgo: 0, [
            (.fish, .medium), (.legumes, .medium), (.vegetables, .medium), (.oliveOil, .medium)
        ])
        let rating = OliveRating.forMeal(dinner)
        #expect(rating.olives == 5)
        #expect(rating.leading.prefix(2) == [.fish, .legumes])
    }

    @Test("One olive says it is a treat, and never says it is a failure")
    func theTreat() {
        let croissant = MealEntry.fixture(daysAgo: 0, [(.pastry, .large), (.butter, .large)])
        let rating = OliveRating.forMeal(croissant)
        #expect(rating.olives == 1)
        #expect(rating.reason() == "A treat — it happens.")
    }

    @Test("The rating never leaves 1...5, however lopsided the plate")
    func clamped() {
        let feast = MealEntry.fixture(daysAgo: 0, Array(
            repeating: (FoodGroup.fish, Portion.large), count: 6
        ))
        #expect(OliveRating.range.contains(OliveRating.forMeal(feast).olives))

        let bender = MealEntry.fixture(daysAgo: 0, [
            (.processedMeat, .large), (.pastry, .large), (.sweets, .large),
            (.sugaryDrinks, .large), (.butter, .large), (.redMeat, .large)
        ])
        #expect(OliveRating.forMeal(bender).olives == OliveRating.range.lowerBound)
    }

    @Test("Four rows of the same group are one plate of it")
    func perMealGroupCapApplies() {
        // The cap lives in `MealEntry.servings(of:)`, and the rating has to read
        // through it: a platter recognized as four separate fruit rows must not
        // be rated as four plates of fruit.
        let platter = MealEntry.fixture(daysAgo: 0, Array(
            repeating: (FoodGroup.vegetables, Portion.medium), count: 4
        ))
        let one = MealEntry.fixture(daysAgo: 0, [(.vegetables, .large)])
        #expect(OliveRating.forMeal(platter).value == OliveRating.forMeal(one).value)
    }

    @Test("A taste of a shared plate is rated as a taste")
    func shareScalesTheRating() {
        var shared = MealEntry.fixture(daysAgo: 0, [(.fish, .medium), (.legumes, .medium)])
        let whole = OliveRating.forMeal(shared).value
        shared.share = .taste
        let taste = OliveRating.forMeal(shared).value
        #expect(taste < whole)
        #expect(taste > OliveRating.neutral)
    }

    @Test("A day with nothing logged has no rating at all")
    func unratedDayIsNotAnAverageDay() {
        // Distinct from three olives on purpose. A screen that draws them alike
        // tells someone they ate averagely on a day they did not eat.
        #expect(OliveRating.forDay([]) == nil)
    }

    @Test("The day weights meals by size, so a coffee cannot outvote dinner")
    func dayIsPortionWeighted() {
        let dinner = MealEntry.fixture(daysAgo: 0, [
            (.fish, .large), (.vegetables, .large), (.oliveOil, .medium)
        ])
        let coffee = MealEntry.fixture(daysAgo: 0, [(.coffee, .small)])
        let plain = OliveRating.forMeal(dinner).value

        let day = OliveRating.forDay([dinner, coffee, coffee, coffee])
        #expect(day != nil)
        // A plain mean of four meals would drag this most of the way back to
        // neutral; a weighted one barely moves it.
        #expect(abs(day!.value - plain) < 0.5)
    }

    @Test("Weights are configurable without a rebuild")
    func weightsComeFromConfig() {
        let plate = MealEntry.fixture(daysAgo: 0, [(.redMeat, .medium)])
        #expect(OliveRating.forMeal(plate).olives < 3)

        // The one number this app has that is a taste rather than a fact, so it
        // has to be movable from `shaman-config.json` like the rest of them.
        let forgiving = OliveConfiguration(weights: [FoodGroup.redMeat.rawValue: 0.5])
        #expect(OliveRating.forMeal(plate, configuration: forgiving).olives > 3)
    }

    @Test("The bundled config carries weights the code agrees with")
    func bundledConfigDecodes() throws {
        let url = try #require(Bundle.module.url(forResource: "shaman-config", withExtension: "json"))
        let config = try JSONDecoder().decode(AppConfig.self, from: Data(contentsOf: url))
        let weights = try #require(config.olives?.weights)
        #expect(weights[FoodGroup.fish.rawValue] == OliveConfiguration.defaultWeights[FoodGroup.fish.rawValue])
        #expect(weights[FoodGroup.pastry.rawValue] == OliveConfiguration.defaultWeights[FoodGroup.pastry.rawValue])
    }
}
