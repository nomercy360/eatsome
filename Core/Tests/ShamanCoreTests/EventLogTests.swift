import Foundation
import Testing
@testable import ShamanCore

@Suite("Event log")
struct EventLogTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("shaman-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("events.jsonl")
    }

    @Test("Events survive a round trip")
    func appendAndLoad() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let meal = MealEntry.fixture(daysAgo: 1, [("salmon", 120.0), ("salad leaves", 220.0)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))
        try await log.append(LoggedEvent(
            occurredAt: meal.eatenAt,
            payload: .setCompleted(SetRecord(movementID: "squat", startedAt: 0, finishedAt: 60_000, reps: 12))
        ))

        let projection = try await log.projection()
        #expect(projection.meals.count == 1)
        #expect(projection.meals[meal.id]?.grams == 340)
        #expect(projection.sets.first?.reps == 12)
    }

    @Test("A revision supersedes the original without erasing the log")
    func revisionSupersedes() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var meal = MealEntry.fixture(daysAgo: 1, [("chicken breast", 120.0)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))

        // The correction that matters: the model said chicken, it was fish.
        meal.dishes = [Fixture.dish(nil, [Fixture.item("salmon", grams: 140)])]
        meal.wasCorrected = true
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealRevised(meal)))

        let (events, _) = try await log.load()
        #expect(events.count == 2, "the original is still on disk — that is the point of append-only")

        let projection = Projection(replaying: events)
        #expect(projection.meals[meal.id]?.items.first?.label == "salmon")
        #expect(projection.meals[meal.id]?.wasCorrected == true)
    }

    @Test("A saved meal retains its complete recognition eval pair")
    func recognitionEvidenceSurvives() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let photoHash = ImageDigest.sha256(Data("photo".utf8))
        let initial = Fixture.item(
            "minced chicken",
            grams: 140,
            alternatives: [.init(label: "minced beef", per100g: Fixture.composition)]
        )
        let meal = MealEntry(
            eatenAt: MealEntry.referenceNow,
            dishes: [Fixture.dish("keema", [Fixture.item("minced beef", grams: 140)])],
            source: .photo,
            photoHash: photoHash,
            recognitionEvidence: MealRecognitionEvidence(
                promptVersion: "meal-v21-test",
                model: "gemini-3.6-flash",
                rawModelJSON: #"{"dishes":[]}"#,
                initialDishes: [Fixture.dish("keema", [initial])]
            ),
            wasCorrected: true
        )

        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))
        let saved = try #require(try await log.projection().meals[meal.id])

        #expect(saved.photoHash == photoHash)
        #expect(saved.recognitionEvidence?.promptVersion == "meal-v21-test")
        #expect(saved.recognitionEvidence?.model == "gemini-3.6-flash")
        let initialItem = saved.recognitionEvidence?.initialDishes.first?.items.first
        #expect(initialItem?.label == "minced chicken")
        // The correction the model itself offered is the one you took: that is
        // the eval row worth having.
        #expect(initialItem?.alternatives.first?.label == "minced beef")
        #expect(saved.items.first?.label == "minced beef")
    }

    @Test("A recipe survives the log and logs a meal with fresh item ids")
    func recipesRoundTrip() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let recipe = Recipe(
            name: "French toast",
            dishes: [Fixture.dish("French toast", [
                Fixture.item("French toast", grams: 220),
                Fixture.item("eggs in the batter", grams: 100),
                Fixture.item("butter for frying", grams: 12)
            ])],
            note: "fried in butter, two eggs and milk in the batter",
            updatedAt: MealEntry.referenceNow
        )
        try await log.append(LoggedEvent(occurredAt: recipe.updatedAt, payload: .recipeSaved(recipe)))

        var projection = try await log.projection()
        let saved = try #require(projection.recipes[recipe.id])
        #expect(saved.items.count == 3)
        #expect(saved.note?.contains("two eggs") == true)

        // The invisible half comes back with it, and the meal is its own event.
        let meal = saved.newMeal(eatenAt: MealEntry.referenceNow)
        #expect(meal.source == .recipe)
        #expect(meal.note == saved.note)
        #expect(meal.items.contains { $0.label == "eggs in the batter" })
        #expect(Set(meal.items.map(\.id)).isDisjoint(with: Set(saved.items.map(\.id))))

        try await log.append(LoggedEvent(occurredAt: recipe.updatedAt, payload: .recipeDeleted(recipeID: recipe.id)))
        projection = try await log.projection()
        #expect(projection.recipes.isEmpty)
    }

    @Test("Meal chooser suggests recent dishes until it has usage history")
    func recentRecipeSuggestions() {
        let older = Recipe(name: "Older", dishes: [], updatedAt: 100)
        let middle = Recipe(name: "Middle", dishes: [], updatedAt: 200)
        let newest = Recipe(name: "Newest", dishes: [], updatedAt: 300)
        let projection = Projection(replaying: [older, middle, newest].map {
            LoggedEvent(occurredAt: $0.updatedAt, payload: .recipeSaved($0))
        })

        #expect(projection.suggestedRecipes(limit: 2).map(\.id) == [newest.id, middle.id])
        #expect(projection.suggestedRecipes(limit: 0).isEmpty)
    }

    @Test("Meal chooser prefers the most logged dishes and uses recency for ties")
    func frequentRecipeSuggestions() {
        let recentUnused = Recipe(name: "New but unused", dishes: [], updatedAt: 400)
        let olderFavourite = Recipe(name: "Favourite", dishes: [], updatedAt: 100)
        let newerTie = Recipe(name: "Newer tie", dishes: [], updatedAt: 300)
        let olderTie = Recipe(name: "Older tie", dishes: [], updatedAt: 200)
        let recipes = [recentUnused, olderFavourite, newerTie, olderTie]
        var events = recipes.map { LoggedEvent(occurredAt: $0.updatedAt, payload: .recipeSaved($0)) }

        let uses: [(Recipe, EpochMillis)] = [
            (olderFavourite, 500), (olderFavourite, 600), (newerTie, 700), (olderTie, 800)
        ]
        for (recipe, time) in uses {
            events.append(LoggedEvent(occurredAt: time, payload: .mealLogged(recipe.newMeal(eatenAt: time))))
        }

        let projection = Projection(replaying: events)
        #expect(projection.suggestedRecipes(limit: 3).map(\.id) == [olderFavourite.id, newerTie.id, olderTie.id])
        #expect(projection.timesLogged(recipeID: olderFavourite.id) == 2)
        #expect(!projection.suggestedRecipes(limit: 4).contains { $0.id == recentUnused.id })
    }

    @Test("Deletion removes from the projection")
    func deletion() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let meal = MealEntry.fixture(daysAgo: 1, [("brownie", 220.0)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealDeleted(mealID: meal.id)))

        #expect(try await log.projection().meals.isEmpty)
    }

    @Test("Replay uses write order when two devices append out of file order")
    func replayUsesRecordedOrder() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let meal = MealEntry.fixture(daysAgo: 1, [("chicken breast", 120.0)])
        var revised = meal
        revised.dishes = [Fixture.dish(nil, [Fixture.item("salmon", grams: 140)])]
        revised.wasCorrected = true

        // A pulled remote correction can be appended before an older local
        // event during repair. recordedAt, not JSONL position or eatenAt, is
        // the total order for folding the union.
        try await log.append(LoggedEvent(
            occurredAt: meal.eatenAt,
            recordedAt: 300,
            payload: .mealRevised(revised)
        ))
        try await log.append(LoggedEvent(
            occurredAt: meal.eatenAt,
            recordedAt: 200,
            payload: .mealLogged(meal)
        ))

        let projection = try await log.projection()
        #expect(projection.meals[meal.id]?.items.first?.label == "salmon")
    }

    @Test("A corrupt line costs one record, not the file")
    func corruptLineIsSkipped() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let meal = MealEntry.fixture(daysAgo: 1, [("chickpeas", 120.0)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))
        await log.close()

        // Simulates a half-written record after a crash.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"id":"not-a-uuid","occurredAt":"#.utf8))
        try handle.close()

        let reopened = try EventLog(url: url)
        let (events, skipped) = try await reopened.load()
        #expect(events.count == 1)
        #expect(skipped == 1)
    }

    @Test("Retired settings are ignored during an upgrade")
    func retiredSettingsAreIgnored() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let retiredLines = [
            #"{"id":"00000000-0000-4000-8000-000000000001","occurredAt":1,"recordedAt":1,"payload":{"kind":"habits_updated","data":{}}}"#,
            #"{"id":"00000000-0000-4000-8000-000000000002","occurredAt":2,"recordedAt":2,"payload":{"kind":"diet_saved","data":{}}}"#,
            #"{"id":"00000000-0000-4000-8000-000000000003","occurredAt":3,"recordedAt":3,"payload":{"kind":"diet_selected","data":{}}}"#
        ]
        try retiredLines.joined(separator: "\n").appending("\n").write(
            to: url,
            atomically: false,
            encoding: .utf8
        )

        let meal = MealEntry.fixture(daysAgo: 1, [("chickpeas", 120.0)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))

        let (events, skipped) = try await log.load()
        #expect(events.count == 1)
        #expect(skipped == 0)
    }

    @Test("Events sort by time, and UUIDv7 carries the timestamp")
    func uuidV7IsTimeOrdered() {
        let earlier = UUIDv7.generate(at: 1_700_000_000_000)
        let later = UUIDv7.generate(at: 1_700_000_060_000)

        #expect(UUIDv7.timestamp(of: earlier) == 1_700_000_000_000)
        #expect(UUIDv7.timestamp(of: later) == 1_700_000_060_000)
        #expect(earlier.uuidString < later.uuidString, "v7 must sort lexicographically by creation time")
        #expect(UUIDv7.timestamp(of: UUID()) == nil, "a v4 UUID carries no timestamp")
    }

    @Test("Projection windows are half-open")
    func projectionWindowing() {
        let base = MealEntry.referenceNow
        let events = [0, 1, 2].map { offset in
            let meal = MealEntry(eatenAt: base + EpochMillis(offset) * 1000,
                                 dishes: [Fixture.dish(nil, [Fixture.item("banana", grams: 120)])], source: .manual)
            return LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal))
        }
        let projection = Projection(replaying: events)
        #expect(projection.meals(from: base, to: base + 2000).count == 2)
    }
}
