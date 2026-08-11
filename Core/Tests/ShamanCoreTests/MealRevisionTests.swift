import Foundation
import Testing
@testable import ShamanCore

@Suite("Correcting a recognition")
struct MealRevisionTests {
    private func current() -> [MealItem] {
        [
            MealItem(group: .refinedGrains, label: "French toast", grams: 180),
            MealItem(group: .fruit, label: "sliced banana", grams: 90),
            // No weight: typed in by hand, or logged before v17.
            MealItem(group: .sweets, label: "syrup drizzle")
        ]
    }

    @Test("A delta adds what the photo could not show and leaves the rest alone")
    func appliesAdditions() {
        let revision = MealRevision(add: [
            .init(group: .egg, grams: 100, label: "eggs in the batter"),
            .init(group: .butter, grams: 12, label: "butter for frying"),
            .init(group: .dairy, grams: 60, label: "milk in the batter")
        ])
        let result = revision.applied(to: current())

        #expect(result.count == 6)
        #expect(result.map(\.group).prefix(3) == [.refinedGrains, .fruit, .sweets])
        #expect(result.first { $0.group == .egg }?.grams == 100)
        #expect(result.first { $0.group == .butter }?.grams == 12)
        #expect(revision.summary == "3 added")
    }

    @Test("Hand-made edits survive: only the named rows change")
    func keepsUntouchedRows() {
        // The person already fixed the weight on row 2 by hand. A full re-run
        // would overwrite it; a delta must not.
        var items = current()
        items[1].grams = 200

        let revision = MealRevision(revise: [.init(index: 1, group: .pastry, grams: 150)])
        let result = revision.applied(to: items)

        #expect(result[0].group == .pastry)
        #expect(result[0].grams == 150)
        #expect(result[1].grams == 200, "row 2 was never mentioned")
        #expect(result[2].group == .sweets)
    }

    @Test("A revision moves the effective serving count")
    func revisionMovesEffectiveServings() {
        // The point of carrying grams. A revise used to set `portion`, which
        // `effectiveServings` never reached on a weighed row: the delta applied,
        // the summary said "1 changed", and the quantity did not move an inch.
        let items = [MealItem(group: .whiteMeat, label: "chicken", grams: 200)]
        let before = items[0].effectiveServings()
        let result = MealRevision(revise: [.init(index: 1, group: .whiteMeat, grams: 100)]).applied(to: items)

        #expect(result[0].grams == 100)
        #expect(result[0].effectiveServings() < before)
    }

    @Test("A revised row keeps one quantity, not two")
    func revisionClearsStaleServings() {
        // A row flattened under the old ladder carries its arithmetic in
        // `servings`. Writing a weight beside it would leave the item saying
        // two different things about how much there was.
        let items = [MealItem(group: .fish, label: "salmon", servings: 2, grams: nil)]
        let result = MealRevision(revise: [.init(index: 1, group: .fish, grams: 140)]).applied(to: items)

        #expect(result[0].grams == 140)
        #expect(result[0].servings == nil)
    }

    @Test("Revising a group drops the model's stale shortlist")
    func revisionClearsAlternatives() {
        let items = [MealItem(group: .whiteMeat, label: "kebab", modelAlternatives: [.redMeat], grams: 150)]
        let result = MealRevision(revise: [.init(index: 1, group: .redMeat, grams: 150)]).applied(to: items)

        #expect(result[0].group == .redMeat)
        #expect(result[0].modelAlternatives == nil)
    }

    @Test("Removals are applied by position, after revisions")
    func appliesRemovals() {
        let result = MealRevision(
            revise: [.init(index: 3, group: .sweets, grams: 25)],
            remove: [2]
        ).applied(to: current())

        #expect(result.count == 2)
        #expect(result.map(\.label) == ["French toast", "syrup drizzle"])
        #expect(result[1].grams == 25, "the revision landed before the removal shifted anything")
    }

    @Test("An index the model invented changes nothing")
    func boundsAreChecked() {
        let items = current()
        let revision = MealRevision(
            revise: [.init(index: 99, group: .redMeat, grams: 200), .init(index: 0, group: .redMeat, grams: 200)],
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
        #expect(message.contains("1. French toast — refined_grains, 180 g"))
        // An unweighed row says so rather than being given a number nobody
        // established — the model is told to leave it alone if the words do not
        // settle it.
        #expect(message.contains("3. syrup drizzle — sweets, no weight recorded"))
        #expect(message.contains("two eggs in the batter"))
        #expect(message.contains("Keep everything else"))

        let system = MealRevisionPrompt.system.lowercased()
        #expect(system.contains("change as little as possible"))
        #expect(system.contains("destroys the person's own corrections"))
        #expect(system.contains("weight is the only number"))
        #expect(!system.contains("coarse portions"))
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

    @Test("What the person said reaches both providers in the same slot")
    func noteTravelsWithThePhoto() throws {
        let note = "fried in butter, two eggs in the batter"

        let luna = LunaSession { "sk-test" }
            .requestBody(for: .photo(Data([0xFF]), said: note))
        let lunaInput = try #require(luna["input"] as? [[String: Any]])
        let lunaText = try #require(
            (lunaInput.last?["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        #expect(lunaText.contains(note))
        #expect(lunaText.contains("What the photo cannot show"))

        let gemini = GeminiSession { "test" }
            .requestBody(for: .photo(Data([0xFF]), said: note))
        let parts = try #require((gemini["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]])
        #expect((parts.first?["text"] as? String)?.contains(note) == true)

        // No note, no ceremony.
        let plain = LunaSession { "sk-test" }.requestBody(for: .photo(Data([0xFF])))
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
            #"{\"add\":[{\"group\":\"egg\",\"grams\":100,\"label\":\"eggs in the batter\",\"alternatives\":[]}],\"revise\":[{\"index\":1,\"group\":\"refined_grains\",\"grams\":180}],\"remove\":[],\"notes\":null}"#

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
            func recognize(_ message: MealMessage) async throws -> RecognitionArtifact {
                await counter.increment()
                return RecognitionArtifact(
                    recognition: MealRecognition(
                        items: [], otherMealsVisible: false, notes: message.trimmedText
                    ),
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

        _ = try await caching.recognize(.photo(photo))
        _ = try await caching.recognize(.photo(photo))
        _ = try await caching.recognize(.photo(photo, said: "fried in butter"))

        #expect(await counter.calls == 2)

        // And two different typed meals with no photograph at all are two
        // questions, not one. Without the words in the key they would share an
        // empty payload and the second would be served the first one's answer —
        // silently, and with no photo to notice it by.
        _ = try await caching.recognize(.words("leftover lentil soup, big bowl"))
        _ = try await caching.recognize(.words("leftover lentil soup, big bowl"))
        _ = try await caching.recognize(.words("hard-boiled egg, black coffee"))

        #expect(await counter.calls == 4)
    }

    @Test("A message with neither words nor a photo never reaches a model")
    func emptyMessageIsRefused() async {
        // An empty prompt does not fail loudly; it returns a confident account
        // of a meal nobody ate. Cheaper and truer to refuse it here.
        await #expect(throws: MealRecognizerError.self) {
            try await LunaSession { "sk-test" }.recognize(MealMessage())
        }
        await #expect(throws: MealRecognizerError.self) {
            try await GeminiSession { "test" }.recognize(.words("   "))
        }
    }

    @Test("Words with no photograph are framed as the whole meal, not as a caption")
    func wordsWithoutAPhotograph() throws {
        let said = "leftover lentil soup, big bowl"

        let luna = LunaSession { "sk-test" }.requestBody(for: .words(said))
        let input = try #require(luna["input"] as? [[String: Any]])
        let content = try #require(input.last?["content"] as? [[String: Any]])
        // No image part at all, rather than an empty one: a zero-length image is
        // a decode error at the vendor, not an absent image.
        #expect(content.count == 1)
        let text = try #require(content.first?["text"] as? String)
        #expect(text.contains(said))
        #expect(!text.contains("What the photo cannot show"))
        #expect(text.contains("in their own words"))

        let gemini = GeminiSession { "test" }.requestBody(for: .words(said))
        let parts = try #require(
            (gemini["contents"] as? [[String: Any]])?.first?["parts"] as? [[String: Any]]
        )
        #expect(parts.count == 1)
        #expect(parts.first?["inlineData"] == nil)
    }
}
