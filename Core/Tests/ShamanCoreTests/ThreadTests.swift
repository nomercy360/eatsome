import Foundation
import Testing
@testable import ShamanCore

@Suite("The thread")
struct ThreadTests {
    private let start = MealEntry.referenceNow - 86_400_000
    private let end = MealEntry.referenceNow + 86_400_000

    private func projection(_ payloads: [EventPayload]) -> Projection {
        Projection(replaying: payloads.map {
            LoggedEvent(occurredAt: MealEntry.referenceNow, payload: $0)
        })
    }

    @Test("A message and the meal it became are one turn, not two")
    func messageAndMealPairUp() {
        let message = LogMessage(sentAt: MealEntry.referenceNow, said: "banana and coffee")
        var meal = MealEntry.fixture(daysAgo: 0, [(.fruit, .medium)])
        meal.messageID = message.id

        let turns = projection([.messageSent(message), .mealLogged(meal)]).thread(from: start, to: end)
        #expect(turns.count == 1)
        #expect(turns.first?.message == message)
        #expect(turns.first?.meal?.id == meal.id)
    }

    @Test("A message still being read is a turn with no meal under it")
    func messageWithoutItsMealYet() {
        let message = LogMessage(sentAt: MealEntry.referenceNow, said: "hard-boiled egg")
        let turns = projection([.messageSent(message)]).thread(from: start, to: end)
        #expect(turns.count == 1)
        #expect(turns.first?.meal == nil)
    }

    @Test("Cards stay under their own bubbles when messages finish out of order")
    func completionOrderDoesNotReorderTheThread() {
        // The whole point of the queue: breakfast is slow, the 11 am photo is
        // quick, and the thread must still read breakfast-then-photo.
        let breakfast = LogMessage(sentAt: MealEntry.referenceNow, said: "french toast")
        let snack = LogMessage(sentAt: MealEntry.referenceNow + 60_000, said: "2 of this")

        var snackMeal = MealEntry.fixture(daysAgo: 0, [(.yogurt, .medium)])
        snackMeal.messageID = snack.id
        var breakfastMeal = MealEntry.fixture(daysAgo: 0, [(.egg, .medium)])
        breakfastMeal.messageID = breakfast.id

        // Applied in completion order: the snack was read first.
        let turns = projection([
            .messageSent(breakfast),
            .messageSent(snack),
            .mealLogged(snackMeal),
            .mealLogged(breakfastMeal)
        ]).thread(from: start, to: end)

        #expect(turns.map(\.message?.id) == [breakfast.id, snack.id])
        #expect(turns.first?.meal?.id == breakfastMeal.id)
    }

    @Test("A meal with no message still appears in the thread")
    func orphanMealsAreVisible() {
        // Anything logged before the thread existed, or added from the day
        // sheet. A meal in history that cannot be seen is a meal you cannot
        // correct.
        let meal = MealEntry.fixture(daysAgo: 0, [(.fish, .medium)])
        let turns = projection([.mealLogged(meal)]).thread(from: start, to: end)
        #expect(turns.count == 1)
        #expect(turns.first?.message == nil)
        #expect(turns.first?.meal?.id == meal.id)
    }

    @Test("A turn keeps its identity as the card arrives underneath")
    func identityIsStableAcrossStates() {
        // A changed id would animate the whole row out and back in at exactly
        // the moment the meal card appears.
        let message = LogMessage(sentAt: MealEntry.referenceNow, said: "lentil soup")
        var meal = MealEntry.fixture(daysAgo: 0, [(.legume, .medium)])
        meal.messageID = message.id

        let reading = projection([.messageSent(message)]).thread(from: start, to: end)
        let logged = projection([.messageSent(message), .mealLogged(meal)]).thread(from: start, to: end)
        #expect(reading.first?.id == logged.first?.id)
    }

    @Test("Deleting a message takes its bubble out of the thread")
    func messageDeletionIsAnEvent() {
        let message = LogMessage(sentAt: MealEntry.referenceNow, said: "a mistake")
        let after = projection([.messageSent(message), .messageDeleted(messageID: message.id)])
        #expect(after.thread(from: start, to: end).isEmpty)
        #expect(after.messages.isEmpty)
    }

    @Test("Messages survive a round trip through the log format")
    func messagesEncodeAndDecode() throws {
        // The log is append-only and read back for years. A payload that cannot
        // decode is a day of the thread that silently disappears.
        let message = LogMessage(
            sentAt: MealEntry.referenceNow,
            said: "3 french toasts — 8 am",
            photoHash: String(repeating: "a", count: 64)
        )
        let event = LoggedEvent(occurredAt: message.sentAt, payload: .messageSent(message))
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(LoggedEvent.self, from: data)

        guard case .messageSent(let restored) = decoded.payload else {
            Issue.record("payload did not survive the round trip")
            return
        }
        #expect(restored == message)

        // The on-disk spelling, which is the half that has to stay stable.
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"message_sent\""))
    }

    @Test("A meal from a build that has never heard of messages still decodes")
    func mealsWithoutAMessageIDDecode() throws {
        // `messageID` is optional for the same reason every stored field added
        // since v1 is: one non-optional addition and every existing line of
        // events.jsonl fails, taking the meals with it.
        let json = """
        {"id":"\(UUID().uuidString)","eatenAt":1700000000000,
         "items":[],"source":"photo","wasCorrected":false}
        """
        let meal = try JSONDecoder().decode(MealEntry.self, from: Data(json.utf8))
        #expect(meal.messageID == nil)
    }

    @Test("A source this build has never seen falls back rather than throwing")
    func unknownSourceDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","eatenAt":1700000000000,
         "items":[],"source":"telepathy","wasCorrected":false}
        """
        let meal = try JSONDecoder().decode(MealEntry.self, from: Data(json.utf8))
        #expect(meal.source == .manual)
    }

    @Test("An empty message is never a message")
    func emptyMessagesAreRefused() {
        #expect(LogMessage().isEmpty)
        #expect(LogMessage(said: "   \n ").isEmpty)
        #expect(!LogMessage(said: "a banana").isEmpty)
        #expect(!LogMessage(photoHash: String(repeating: "b", count: 64)).isEmpty)
    }
}

@Suite("Dayparts")
struct DaypartTests {
    @Test("The frames' own times land in the frames' own labels")
    func matchesTheDesign() {
        #expect(Daypart(hour: 8).displayName == "Breakfast")
        #expect(Daypart(hour: 11).displayName == "Snack")
        #expect(Daypart(hour: 13).displayName == "Lunch")
        #expect(Daypart(hour: 19).displayName == "Dinner")
        #expect(Daypart(hour: 2).displayName == "Late")
    }

    @Test("Either side of midnight is one eating occasion")
    func lateWrapsMidnight() {
        #expect(Daypart(hour: 23) == .late)
        #expect(Daypart(hour: 1) == .late)
    }

    @Test("Every hour of the day has a daypart")
    func totalOverTheClock() {
        for hour in 0..<24 { _ = Daypart(hour: hour) }
    }
}
