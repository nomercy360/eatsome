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

        let meal = MealEntry.fixture(daysAgo: 1, [(.fish, .medium), (.vegetables, .large)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))
        try await log.append(LoggedEvent(
            occurredAt: meal.eatenAt,
            payload: .setCompleted(SetRecord(movementID: "squat", startedAt: 0, finishedAt: 60_000, reps: 12))
        ))

        let projection = try await log.projection()
        #expect(projection.meals.count == 1)
        #expect(projection.meals[meal.id]?.servings(of: .vegetables) == 2.0)
        #expect(projection.sets.first?.reps == 12)
    }

    @Test("A revision supersedes the original without erasing the log")
    func revisionSupersedes() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var meal = MealEntry.fixture(daysAgo: 1, [(.whiteMeat, .medium)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))

        // The correction that matters: the model said chicken, it was fish.
        meal.items = [MealItem(group: .fish, portion: .medium)]
        meal.wasCorrected = true
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealRevised(meal)))

        let (events, _) = try await log.load()
        #expect(events.count == 2, "the original is still on disk — that is the point of append-only")

        let projection = Projection(replaying: events)
        #expect(projection.meals[meal.id]?.items.first?.group == .fish)
        #expect(projection.meals[meal.id]?.wasCorrected == true)
    }

    @Test("A saved meal retains its complete recognition eval pair")
    func recognitionEvidenceSurvives() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let photoHash = ImageDigest.sha256(Data("photo".utf8))
        let initial = MealItem(
            group: .whiteMeat,
            portion: .medium,
            label: "minced meat",
            modelAlternatives: [.redMeat]
        )
        let meal = MealEntry(
            eatenAt: MealEntry.referenceNow,
            items: [MealItem(group: .redMeat, portion: .medium, label: "minced meat")],
            source: .photo,
            photoHash: photoHash,
            recognitionEvidence: MealRecognitionEvidence(
                promptVersion: "meal-v3-test",
                rawModelJSON: #"{"items":[{"group":"white_meat","alternatives":["red_meat"]}]}"#,
                initialItems: [initial],
                otherMealsVisible: true
            ),
            wasCorrected: true
        )

        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))
        let saved = try #require(try await log.projection().meals[meal.id])

        #expect(saved.photoHash == photoHash)
        #expect(saved.recognitionEvidence?.promptVersion == "meal-v3-test")
        #expect(saved.recognitionEvidence?.rawModelJSON.contains("white_meat") == true)
        #expect(saved.recognitionEvidence?.initialItems.first?.group == .whiteMeat)
        // The correction the model itself offered is the one you took: that is
        // the eval row worth having.
        #expect(saved.recognitionEvidence?.initialItems.first?.modelAlternatives == [.redMeat])
        #expect(saved.items.first?.group == .redMeat)
        #expect(saved.recognitionEvidence?.otherMealsVisible == true)
    }

    @Test("A recipe survives the log and logs a meal with fresh item ids")
    func recipesRoundTrip() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let recipe = Recipe(
            name: "French toast",
            items: [
                MealItem(group: .refinedGrains, portion: .large, label: "French toast"),
                MealItem(group: .egg, portion: .medium, label: "eggs in the batter"),
                MealItem(group: .butter, portion: .small, label: "butter for frying")
            ],
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
        #expect(meal.servings(of: .egg) == 1.0)
        #expect(Set(meal.items.map(\.id)).isDisjoint(with: Set(saved.items.map(\.id))))

        try await log.append(LoggedEvent(occurredAt: recipe.updatedAt, payload: .recipeDeleted(recipeID: recipe.id)))
        projection = try await log.projection()
        #expect(projection.recipes.isEmpty)
    }

    @Test("Deletion removes from the projection")
    func deletion() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let meal = MealEntry.fixture(daysAgo: 1, [(.sweets, .large)])
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal)))
        try await log.append(LoggedEvent(occurredAt: meal.eatenAt, payload: .mealDeleted(mealID: meal.id)))

        #expect(try await log.projection().meals.isEmpty)
    }

    @Test("A corrupt line costs one record, not the file")
    func corruptLineIsSkipped() async throws {
        let url = temporaryURL()
        let log = try EventLog(url: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let meal = MealEntry.fixture(daysAgo: 1, [(.legumes, .medium)])
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
                                 items: [MealItem(group: .fruit, portion: .medium)], source: .manual)
            return LoggedEvent(occurredAt: meal.eatenAt, payload: .mealLogged(meal))
        }
        let projection = Projection(replaying: events)
        #expect(projection.meals(from: base, to: base + 2000).count == 2)
    }
}
