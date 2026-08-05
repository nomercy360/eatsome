import Foundation
import Testing
@testable import ShamanCore

@Suite("Correcting a recognition")
struct MealRevisionTests {
    private func current() -> [MealItem] {
        [
            MealItem(group: .refinedGrains, portion: .large, label: "French toast"),
            MealItem(group: .fruit, portion: .medium, label: "sliced banana"),
            MealItem(group: .sweets, portion: .small, label: "syrup drizzle")
        ]
    }

    @Test("A delta adds what the photo could not show and leaves the rest alone")
    func appliesAdditions() {
        let revision = MealRevision(add: [
            .init(group: .egg, portion: .medium, label: "eggs in the batter"),
            .init(group: .butter, portion: .small, label: "butter for frying"),
            .init(group: .dairy, portion: .small, label: "milk in the batter")
        ])
        let result = revision.applied(to: current())

        #expect(result.count == 6)
        #expect(result.map(\.group).prefix(3) == [.refinedGrains, .fruit, .sweets])
        #expect(result.contains { $0.group == .egg })
        #expect(result.contains { $0.group == .butter })
        #expect(revision.summary == "3 added")
    }

    @Test("Hand-made edits survive: only the named rows change")
    func keepsUntouchedRows() {
        // The person already fixed the portion on row 2 by hand. A full re-run
        // would overwrite it; a delta must not.
        var items = current()
        items[1].portion = .large

        let revision = MealRevision(revise: [.init(index: 1, group: .pastry, portion: .medium)])
        let result = revision.applied(to: items)

        #expect(result[0].group == .pastry)
        #expect(result[0].portion == .medium)
        #expect(result[1].portion == .large, "row 2 was never mentioned")
        #expect(result[2].group == .sweets)
    }

    @Test("Revising a group drops the model's stale shortlist")
    func revisionClearsAlternatives() {
        let items = [MealItem(group: .whiteMeat, portion: .medium, label: "kebab", modelAlternatives: [.redMeat])]
        let result = MealRevision(revise: [.init(index: 1, group: .redMeat, portion: .medium)]).applied(to: items)

        #expect(result[0].group == .redMeat)
        #expect(result[0].modelAlternatives == nil)
    }

    @Test("Removals are applied by position, after revisions")
    func appliesRemovals() {
        let result = MealRevision(
            revise: [.init(index: 3, group: .sweets, portion: .medium)],
            remove: [2]
        ).applied(to: current())

        #expect(result.count == 2)
        #expect(result.map(\.label) == ["French toast", "syrup drizzle"])
        #expect(result[1].portion == .medium, "the revision landed before the removal shifted anything")
    }

    @Test("An index the model invented changes nothing")
    func boundsAreChecked() {
        let items = current()
        let revision = MealRevision(
            revise: [.init(index: 99, group: .redMeat, portion: .large), .init(index: 0, group: .redMeat, portion: .large)],
            remove: [42, -1]
        )
        #expect(revision.applied(to: items) == items)
    }

    @Test("The correction prompt shows a numbered list and fences the person's words")
    func revisionMessageShape() {
        let message = MealRevisionPrompt.message(
            current: current(),
            note: "fried in butter, two eggs in the batter"
        )
        #expect(message.contains("1. French toast — refined_grains, large"))
        #expect(message.contains("3. syrup drizzle — sweets, small"))
        #expect(message.contains("two eggs in the batter"))
        #expect(message.contains("Keep everything else"))

        let system = MealRevisionPrompt.system.lowercased()
        #expect(system.contains("change as little as possible"))
        #expect(system.contains("destroys the person's own corrections"))
        #expect(!system.contains("calories,") || system.contains("never calories"))
    }

    @Test("Both revision schemas match the food groups the app knows")
    func revisionSchemas() throws {
        let openAI = MealRevisionPrompt.jsonSchema
        #expect(openAI["additionalProperties"] as? Bool == false)
        let properties = try #require(openAI["properties"] as? [String: Any])
        #expect(Set(try #require(openAI["required"] as? [String])) == Set(properties.keys))

        let addition = try #require((properties["add"] as? [String: Any])?["items"] as? [String: Any])
        let groups = try #require(
            ((addition["properties"] as? [String: Any])?["group"] as? [String: Any])?["enum"] as? [String]
        )
        #expect(Set(groups) == Set(FoodGroup.allCases.map(\.rawValue)))

        // Gemini rejects `additionalProperties`, so the mirror must not carry it.
        #expect(!MealRevisionPrompt.geminiResponseSchema.description.contains("additionalProperties"))
    }

    @Test("A note reaches both providers in the same slot")
    func noteTravelsWithThePhoto() throws {
        let note = "fried in butter, two eggs in the batter"

        let luna = LunaSession { "sk-test" }
            .requestBody(imageData: Data([0xFF]), mimeType: "image/jpeg", note: note)
        let lunaInput = try #require(luna["input"] as? [[String: Any]])
        let lunaText = try #require(
            (lunaInput.last?["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        #expect(lunaText.contains(note))
        #expect(lunaText.contains("What the photo cannot show"))

        let gemini = GeminiSession { "test" }
            .requestBody(imageData: Data([0xFF]), mimeType: "image/jpeg", note: note)
        let parts = try #require((gemini["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])
        #expect((parts.first?["text"] as? String)?.contains(note) == true)

        // No note, no ceremony.
        let plain = LunaSession { "sk-test" }.requestBody(imageData: Data([0xFF]), mimeType: "image/jpeg")
        let plainInput = try #require(plain["input"] as? [[String: Any]])
        let plainText = try #require(
            (plainInput.last?["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        #expect(plainText == MealPrompt.user)
    }

    @Test("The correction request carries the photo and the current list")
    func revisionRequestShape() throws {
        let body = LunaSession { "sk-test" }.revisionRequestBody(
            imageData: Data([0xFF, 0xD8]),
            mimeType: "image/jpeg",
            current: current(),
            note: "missing the eggs"
        )
        let input = try #require(body["input"] as? [[String: Any]])
        #expect((input.first?["content"] as? [[String: Any]])?.first?["text"] as? String == MealRevisionPrompt.system)

        let userContent = try #require(input.last?["content"] as? [[String: Any]])
        #expect((userContent.first?["text"] as? String)?.contains("French toast") == true)
        #expect(userContent.contains { $0["type"] as? String == "input_image" })

        let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
        #expect(format?["name"] as? String == "meal_revision")
        #expect(format?["strict"] as? Bool == true)

        // A recipe or a manual entry has no photograph, and refinement still works.
        let textOnly = GeminiSession { "test" }.revisionRequestBody(
            imageData: nil, mimeType: "image/jpeg", current: current(), note: "missing the eggs"
        )
        let parts = try #require((textOnly["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])
        #expect(parts.count == 1)
    }

    @Test("A model's delta decodes from either provider")
    func parsesRevisionResponses() throws {
        let payload =
            #"{\"add\":[{\"group\":\"egg\",\"portion\":\"medium\",\"label\":\"eggs in the batter\",\"alternatives\":[]}],\"revise\":[{\"index\":1,\"group\":\"refined_grains\",\"portion\":\"medium\"}],\"remove\":[],\"notes\":null}"#

        let luna = """
        {"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"\(payload)"}]}]}
        """
        let fromLuna = try LunaSession.parseRevision(Data(luna.utf8))
        #expect(fromLuna.add.first?.group == .egg)
        #expect(fromLuna.revise.first?.index == 1)

        let gemini = """
        {"candidates":[{"content":{"parts":[{"text":"\(payload)"}]},"finishReason":"STOP"}]}
        """
        let fromGemini = try GeminiSession.parseRevision(Data(gemini.utf8))
        #expect(fromGemini.add.first?.label == "eggs in the batter")
        #expect(fromGemini.summary == "1 added, 1 changed")
    }

    @Test("Adding a note to a photo asks again instead of replaying the answer")
    func noteIsPartOfTheCacheKey() async throws {
        actor Counter {
            var calls = 0
            func increment() { calls += 1 }
        }
        struct Stub: MealRecognizer {
            let counter: Counter
            func recognize(imageData: Data, mimeType: String, note: String?) async throws -> RecognitionArtifact {
                await counter.increment()
                return RecognitionArtifact(
                    recognition: MealRecognition(items: [], otherMealsVisible: false, notes: note),
                    rawModelJSON: "{}",
                    promptVersion: "stub"
                )
            }
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shaman-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let counter = Counter()
        let caching = try CachingRecognizer(upstream: Stub(counter: counter), directory: directory)
        let photo = Data("pretend jpeg".utf8)

        _ = try await caching.recognize(imageData: photo, mimeType: "image/jpeg", note: nil)
        _ = try await caching.recognize(imageData: photo, mimeType: "image/jpeg", note: nil)
        _ = try await caching.recognize(imageData: photo, mimeType: "image/jpeg", note: "fried in butter")

        #expect(await counter.calls == 2)
    }
}
