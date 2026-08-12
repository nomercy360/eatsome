import Foundation
import Testing
@testable import ShamanCore

@Suite("Gemini recognition")
struct GeminiSessionTests {
    private func session(_ configuration: GeminiSession.Configuration = .init()) -> GeminiSession {
        GeminiSession(configuration: configuration) { "test-key" }
    }

    @Test("Request carries the system prompt, the inline image, and a JSON schema")
    func requestShape() throws {
        let body = session().requestBody(for: .photo(Data([0xFF, 0xD8, 0xFF])))

        let instruction = try #require(body["systemInstruction"] as? [String: Any])
        let instructionParts = try #require(instruction["parts"] as? [[String: Any]])
        #expect(instructionParts.first?["text"] as? String == MealPrompt.system)

        let contents = try #require(body["contents"] as? [[String: Any]])
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        #expect(parts.first?["text"] as? String == MealPrompt.user)
        let inline = try #require(parts.last?["inlineData"] as? [String: Any])
        #expect(inline["mimeType"] as? String == "image/jpeg")
        #expect(inline["data"] as? String == Data([0xFF, 0xD8, 0xFF]).base64EncodedString())

        let generation = try #require(body["generationConfig"] as? [String: Any])
        #expect(generation["responseMimeType"] as? String == "application/json")
        #expect((generation["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "low")
        // Unset by default: an unrecognized enum spelling fails the whole call.
        #expect(generation["mediaResolution"] == nil)
    }

    @Test("The endpoint is versioned, model-scoped, and takes the key in a header")
    func endpoint() throws {
        let url = try #require(GeminiSession.Configuration(model: "gemini-3.6-flash").endpoint)
        #expect(
            url.absoluteString
                == "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent"
        )
        #expect(!url.absoluteString.contains("key="), "an API key in a URL ends up in logs")
    }

    @Test("The response schema stays in Gemini's OpenAPI subset")
    func schemaIsGeminiShaped() throws {
        let schema = GeminiSession.responseSchema
        #expect(schema["type"] as? String == "OBJECT")
        #expect(Set(try #require(schema["required"] as? [String])) == ["dishes"])
        // Gemini rejects this keyword outright rather than ignoring it.
        #expect(!schema.description.contains("additionalProperties"))

        let properties = try #require(schema["properties"] as? [String: Any])
        let dishSchema = try #require((properties["dishes"] as? [String: Any])?["items"] as? [String: Any])
        let dishProperties = try #require(dishSchema["properties"] as? [String: Any])
        let itemSchema = try #require((dishProperties["ingredients"] as? [String: Any])?["items"] as? [String: Any])
        let itemProperties = try #require(itemSchema["properties"] as? [String: Any])
        #expect(Set(try #require(itemSchema["required"] as? [String])) == [
            "label", "grams", "per_100g", "preparation", "brand", "sizes", "alternatives"
        ])
        // Gemini emits exactly the properties this schema names, which is how a
        // missing `grams` went unnoticed for a version: the prompt asked for a
        // weight and the schema had nowhere to put one.
        #expect(itemProperties["grams"] != nil)
        #expect(itemProperties["portion"] == nil)

        // With no table behind the app, a silently missing composition block is
        // a meal worth zero calories — the `grams` failure again, one field over.
        let composition = try #require(itemProperties["per_100g"] as? [String: Any])
        #expect(Set(try #require(composition["required"] as? [String])) == [
            "protein", "fat", "carbohydrate", "kcal", "sodium_mg"
        ])
        // An alternative is priced with the same block, or choosing one in the
        // client swaps the name and leaves the old numbers behind.
        let alternatives = try #require(itemProperties["alternatives"] as? [String: Any])
        let alternative = try #require(alternatives["items"] as? [String: Any])
        let alternativeProperties = try #require(alternative["properties"] as? [String: Any])
        #expect(alternativeProperties["per_100g"] != nil)

        // Labels are required — they are the whole identity now.
        #expect((itemProperties["label"] as? [String: Any])?["nullable"] == nil)
        #expect(properties["notes"] == nil)
        #expect(properties["other_meals_visible"] == nil)
    }

    @Test("A well-formed response decodes")
    func parsesSuccess() throws {
        let json = """
        {"candidates":[{"content":{"role":"model","parts":[
          {"thought":true,"text":"ignore me"},
          {"text":"{\\"dishes\\":[{\\"name\\":\\"beef bowl\\",\\"count\\":1,\\"panel\\":null,\\"ingredients\\":[{\\"grams\\":120,\\"label\\":\\"minced beef\\",\\"per_100g\\":{\\"protein\\":26.1,\\"fat\\":15.4,\\"carbohydrate\\":0,\\"kcal\\":250,\\"sodium_mg\\":72},\\"preparation\\":[\\"pan_fried\\"],\\"alternatives\\":[{\\"label\\":\\"minced pork\\",\\"per_100g\\":{\\"protein\\":25.7,\\"fat\\":20.8,\\"carbohydrate\\":0,\\"kcal\\":297,\\"sodium_mg\\":70}}]}]}]}"}
        ]},"finishReason":"STOP"}]}
        """
        let artifact = try GeminiSession.parse(Data(json.utf8), promptVersion: "test/gemini")
        let item = try #require(artifact.recognition.dishes.first?.ingredients.first)

        #expect(item.label == "minced beef")
        #expect(item.per100g.kcal == 250)
        #expect(item.preparation == [.panFried])
        #expect(item.alternatives.first?.label == "minced pork")
        #expect(item.alternatives.first?.per100g.fat == 20.8)
        #expect(artifact.promptVersion == "test/gemini")
        #expect(!artifact.rawModelJSON.contains("ignore me"), "thought parts are not model output")
    }

    @Test("A truncated answer is an error, not a meal that quietly lost food")
    func parsesTruncated() {
        let json = """
        {"candidates":[{"content":{"parts":[{"text":"{\\"items\\":["}]},"finishReason":"MAX_TOKENS"}]}
        """
        #expect(throws: MealRecognizerError.self) { try GeminiSession.parse(Data(json.utf8)) }
    }

    @Test("A blocked prompt is surfaced, not decoded into an empty meal")
    func parsesBlocked() {
        let json = #"{"promptFeedback":{"blockReason":"SAFETY"},"candidates":[]}"#
        #expect(throws: MealRecognizerError.self) { try GeminiSession.parse(Data(json.utf8)) }
    }

    @Test("A missing API key fails before any network call")
    func missingKey() async {
        let noKey = GeminiSession { nil }
        await #expect(throws: MealRecognizerError.self) {
            try await noKey.recognize(.photo(Data([0x01])))
        }
    }

    @Test("The same photo read by two generators is two cache entries")
    func cacheIsNamespacedByGenerator() async throws {
        actor Counter {
            var calls = 0
            func increment() -> Int {
                calls += 1
                return calls
            }
        }
        struct Stub: MealRecognizer {
            let counter: Counter
            func recognize(_ message: MealMessage) async throws -> RecognitionArtifact {
                let call = await counter.increment()
                return RecognitionArtifact(
                    recognition: MealRecognition(dishes: [
                        .init(
                            name: "salad",
                            ingredients: [
                                .init(
                                    label: "call \(call)",
                                    grams: 90,
                                    per100g: Fixture.composition
                                )
                            ]
                        )
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
        let photo = Data("pretend jpeg".utf8)
        let luna = try CachingRecognizer(
            upstream: Stub(counter: counter), directory: directory, namespace: "meal-v3/gpt-5.6-luna"
        )
        let gemini = try CachingRecognizer(
            upstream: Stub(counter: counter), directory: directory, namespace: "meal-v3/gemini-3.6-flash"
        )

        _ = try await luna.recognize(.photo(photo))
        _ = try await luna.recognize(.photo(photo))
        _ = try await gemini.recognize(.photo(photo))

        #expect(await counter.calls == 2, "the second provider must not replay the first one's answer")
    }
}
