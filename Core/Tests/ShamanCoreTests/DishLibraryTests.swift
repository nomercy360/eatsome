import Foundation
import Testing
@testable import ShamanCore

@Suite("Repeat dishes")
struct DishLibraryTests {
    /// A meal of one named dish, at a given hour, a given number of days back.
    private func meal(
        _ name: String,
        daysAgo: Double,
        hour: Int,
        kind: FoodKind = .legume,
        grams: Double = 300
    ) -> MealEntry {
        var day = Date(epochMillis: MealEntry.referenceNow - EpochMillis(daysAgo * 86_400_000))
        var parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = 0
        day = Calendar.current.date(from: parts) ?? day

        let dish = MealDish(name: name, items: [MealItem(kind: kind, grams: grams)])
        return MealEntry(
            eatenAt: day.epochMillis,
            items: dish.flattened(),
            source: .photo,
            storedDishes: [dish]
        )
    }

    @Test("A dish earns its chip by being logged, and carries the count")
    func countsComeFromTheLog() {
        let meals = [
            meal("lentil soup", daysAgo: 1, hour: 13),
            meal("lentil soup", daysAgo: 3, hour: 13),
            meal("tuna sandwich", daysAgo: 2, hour: 13)
        ]
        let entries = DishLibrary.entries(in: meals)
        #expect(entries.first?.name == "lentil soup")
        #expect(entries.first?.timesLogged == 2)
        #expect(entries.count == 2)
    }

    @Test("Typing filters before ranking, so a rare match still surfaces")
    func typingFilters() {
        let meals = [
            meal("greek yoghurt", daysAgo: 0, hour: 8),
            meal("greek yoghurt", daysAgo: 1, hour: 8),
            meal("greek yoghurt", daysAgo: 2, hour: 8),
            meal("lentil salad", daysAgo: 5, hour: 13)
        ]
        let at = Date(epochMillis: MealEntry.referenceNow)
        let filtered = DishLibrary.suggestions(in: meals, at: at, typed: "len")
        #expect(filtered.map(\.name) == ["lentil salad"])
    }

    @Test("A word inside the name matches, because that is the word people reach for")
    func matchesOnWordBoundaries() {
        let meals = [meal("lentil soup", daysAgo: 1, hour: 13)]
        let at = Date(epochMillis: MealEntry.referenceNow)
        #expect(DishLibrary.suggestions(in: meals, at: at, typed: "soup").count == 1)
        #expect(DishLibrary.suggestions(in: meals, at: at, typed: "oup").isEmpty)
    }

    @Test("Lunch outranks breakfast at lunchtime, even on fewer logs")
    func daypartMatters() {
        // Frequency alone would offer porridge at 1 pm forever.
        var meals = (0..<6).map { meal("porridge", daysAgo: Double($0), hour: 8) }
        meals += (0..<3).map { meal("lentil soup", daysAgo: Double($0), hour: 13) }

        var lunchtime = Calendar.current.dateComponents(
            [.year, .month, .day], from: Date(epochMillis: MealEntry.referenceNow)
        )
        lunchtime.hour = 13
        let at = Calendar.current.date(from: lunchtime) ?? Date(epochMillis: MealEntry.referenceNow)

        #expect(DishLibrary.suggestions(in: meals, at: at, limit: 1).first?.name == "lentil soup")
    }

    @Test("A dish you stopped making stops being offered")
    func recencyDecays() {
        // Six of something in March against two of something last week: at a
        // fourteen-day half-life, four months of silence is worth more than the
        // difference in count.
        var meals = (0..<6).map { meal("stew", daysAgo: 120 + Double($0), hour: 19) }
        meals += (0..<2).map { meal("roast chicken", daysAgo: Double($0), hour: 19) }

        var dinner = Calendar.current.dateComponents(
            [.year, .month, .day], from: Date(epochMillis: MealEntry.referenceNow)
        )
        dinner.hour = 19
        let at = Calendar.current.date(from: dinner) ?? Date(epochMillis: MealEntry.referenceNow)

        #expect(DishLibrary.suggestions(in: meals, at: at, limit: 1).first?.name == "roast chicken")
    }

    @Test("The unnamed dish corrections land in is never offered as a chip")
    func unnamedDishesAreSkipped() {
        // `MealDish.regrouped` files anything a correction added under "", and
        // an empty chip is not something anyone can tap.
        let dish = MealDish(name: "", items: [MealItem(kind: .oil, grams: 10)])
        let orphan = MealEntry(
            eatenAt: MealEntry.referenceNow,
            items: dish.flattened(),
            source: .photo,
            storedDishes: [dish]
        )
        #expect(DishLibrary.entries(in: [orphan]).isEmpty)
    }

    @Test("Tapping a chip logs the dish as it was last logged, with no model call")
    func chipLogsTheKnownDish() {
        let meals = [
            meal("lentil soup", daysAgo: 9, hour: 13, grams: 100),
            meal("lentil soup", daysAgo: 1, hour: 13, grams: 320)
        ]
        let entry = DishLibrary.entries(in: meals)[0]
        #expect(entry.lastLogged.items.first?.grams == 320, "the newest logging is the one repeated")

        let fresh = entry.newMeal(eatenAt: MealEntry.referenceNow)
        #expect(fresh.storedDishes?.first?.name == "lentil soup")
        #expect(fresh.items.first?.grams == 320)
        #expect(fresh.source == .recipe)

        // Fresh item ids: two dinners of the same dish are two events, and
        // sharing ids would make the log lie about which one was corrected.
        #expect(fresh.items.first?.id != meals[1].items.first?.id)
    }

    @Test("A dish logged today outranks the same dish logged last week")
    func tiesBreakOnRecency() {
        let meals = [
            meal("soup a", daysAgo: 7, hour: 13),
            meal("soup b", daysAgo: 0, hour: 13)
        ]
        var lunchtime = Calendar.current.dateComponents(
            [.year, .month, .day], from: Date(epochMillis: MealEntry.referenceNow)
        )
        lunchtime.hour = 13
        let at = Calendar.current.date(from: lunchtime) ?? Date(epochMillis: MealEntry.referenceNow)
        #expect(DishLibrary.suggestions(in: meals, at: at, limit: 1).first?.name == "soup b")
    }

    @Test("An empty log offers nothing rather than crashing")
    func emptyLog() {
        #expect(DishLibrary.suggestions(in: [MealEntry](), typed: "len").isEmpty)
        #expect(DishLibrary.suggestions(in: [MealEntry](), limit: 0).isEmpty)
    }
}
