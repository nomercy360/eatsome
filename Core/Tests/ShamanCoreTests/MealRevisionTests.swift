import Foundation
import Testing
@testable import ShamanCore

@Suite("Correcting a recognition")
struct MealRevisionTests {
    private static let egg = Nutrients(protein: 12.6, fat: 10.6, carbohydrate: 1.1, kcal: 155, sodium: 124)
    private static let butter = Nutrients(protein: 0.9, fat: 81.1, carbohydrate: 0.1, kcal: 717, sodium: 11)

    private func current() -> [MealItem] {
        [
            Fixture.item("French toast", grams: 180),
            Fixture.item("sliced banana", grams: 90),
            Fixture.item("syrup drizzle", grams: 20)
        ]
    }

    @Test("A delta adds what the photo could not show and leaves the rest alone")
    func appliesAdditions() {
        let revision = MealRevision(add: [
            .init(label: "eggs in the batter", grams: 100, per100g: Self.egg),
            .init(label: "butter for frying", grams: 12, per100g: Self.butter),
            .init(label: "milk in the batter", grams: 60, per100g: Fixture.composition)
        ])
        let result = revision.applied(to: current())

        #expect(result.count == 6)
        #expect(result.map(\.label).prefix(3) == ["French toast", "sliced banana", "syrup drizzle"])
        #expect(result.first { $0.label == "eggs in the batter" }?.grams == 100)
        #expect(result.first { $0.label == "butter for frying" }?.per100g.fat == 81.1)
        #expect(revision.summary == "3 added")
    }

    @Test("Hand-made edits survive: only the named rows change")
    func keepsUntouchedRows() {
        // The person already fixed the weight on row 2 by hand. A full re-run
        // would overwrite it; a delta must not.
        var items = current()
        items[1].grams = 200

        let revision = MealRevision(revise: [
            .init(index: 1, label: "brioche french toast", grams: 150, per100g: Fixture.composition)
        ])
        let result = revision.applied(to: items)

        #expect(result[0].label == "brioche french toast")
        #expect(result[0].grams == 150)
        #expect(result[1].grams == 200, "row 2 was never mentioned")
        #expect(result[2].label == "syrup drizzle")
    }

    @Test("A revision moves the weight, which is what a correction is for")
    func revisionMovesWeight() {
        // A revise used to set `portion`, which never reached a weighed row:
        // the delta applied, the summary said "1 changed", and the quantity did
        // not move an inch.
        let items = [Fixture.item("chicken", grams: 200)]
        let result = MealRevision(revise: [
            .init(index: 1, label: "chicken", grams: 100, per100g: Fixture.composition)
        ]).applied(to: items)

        #expect(result[0].grams == 100)
        #expect(result[0].nutrients.kcal == Fixture.composition.kcal)
    }

    @Test("A revision restates the composition, so the figures follow the food")
    func revisionRestatesComposition() {
        // The desync guard. A row renamed from "chicken" to "fried chicken"
        // whose numbers stayed behind is worse than an uncorrected one, because
        // it looks corrected.
        let items = [Fixture.item("chicken breast", grams: 180)]
        let fried = Nutrients(protein: 22.0, fat: 12.1, carbohydrate: 8.9, kcal: 240, sodium: 480)
        let result = MealRevision(revise: [
            .init(index: 1, label: "fried chicken", grams: 180, per100g: fried, preparation: [.deepFried])
        ]).applied(to: items)

        #expect(result[0].label == "fried chicken")
        #expect(result[0].per100g == fried)
        #expect(result[0].preparation == [.deepFried])
        // The person is why it changed, even though a model wrote the numbers.
        #expect(result[0].provenance.kcal == .user)
    }

    @Test("Revising a food drops the model's stale shortlist")
    func revisionClearsAlternatives() {
        let items = [Fixture.item(
            "kebab",
            grams: 150,
            alternatives: [.init(label: "beef kebab", per100g: Fixture.composition)]
        )]
        let result = MealRevision(revise: [
            .init(index: 1, label: "beef kebab", grams: 150, per100g: Fixture.composition)
        ]).applied(to: items)

        #expect(result[0].label == "beef kebab")
        #expect(result[0].alternatives.isEmpty)
    }

    @Test("Removals are applied by position, after revisions")
    func appliesRemovals() {
        let result = MealRevision(
            revise: [.init(index: 3, label: "syrup drizzle", grams: 25, per100g: Fixture.composition)],
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
            revise: [
                .init(index: 99, label: "beef", grams: 200, per100g: Fixture.composition),
                .init(index: 0, label: "beef", grams: 200, per100g: Fixture.composition)
            ],
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
        #expect(message.contains("1. French toast, 180 g"))
        #expect(message.contains("3. syrup drizzle, 20 g"))
        #expect(message.contains("two eggs in the batter"))
        #expect(message.contains("Keep everything else"))

        let system = MealRevisionPrompt.system.lowercased()
        #expect(system.contains("smallest possible delta"))
        // The desync guard, stated to the model as well as enforced in the type.
        #expect(system.contains("as it now stands"))
        #expect(system.contains("looks corrected"))
        #expect(!system.contains("`kind`"))
    }

    @Test("Both revision schemas require the figures a correction moves")
    func revisionSchemas() throws {
        let openAI = MealRevisionPrompt.jsonSchema
        #expect(openAI["additionalProperties"] as? Bool == false)
        let properties = try #require(openAI["properties"] as? [String: Any])
        #expect(Set(try #require(openAI["required"] as? [String])) == Set(properties.keys))

        // A revise that could omit `per_100g` is a row that can be renamed while
        // keeping the old numbers — corrected-looking and wrong.
        for key in ["add", "revise"] {
            let block = try #require((properties[key] as? [String: Any])?["items"] as? [String: Any])
            #expect(try #require(block["required"] as? [String]).contains("per_100g"))
        }

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
            #"{\"add\":[{\"label\":\"eggs in the batter\",\"grams\":100,\"per_100g\":{\"protein\":12.6,\"fat\":10.6,\"carbohydrate\":1.1,\"kcal\":155,\"sodium_mg\":124},\"preparation\":[],\"alternatives\":[]}],\"revise\":[{\"index\":1,\"label\":\"French toast\",\"grams\":180,\"per_100g\":{\"protein\":12.6,\"fat\":10.6,\"carbohydrate\":1.1,\"kcal\":155,\"sodium_mg\":124},\"preparation\":[]}],\"remove\":[],\"notes\":null}"#

        let luna = """
        {"status":"completed","output":[{"type":"message","content":[{"type":"output_text","text":"\(payload)"}]}]}
        """
        let fromLuna = try LunaSession.parseRevision(Data(luna.utf8))
        #expect(fromLuna.add.first?.per100g.protein == 12.6)
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
                    recognition: MealRecognition(dishes: [
                        .init(name: message.trimmedText ?? "meal", ingredients: [])
                    ]),
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
