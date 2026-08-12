import Foundation
import Testing
@testable import ShamanCore

@Suite("Luna recognition")
struct LunaSessionTests {
    private func session(_ configuration: LunaSession.Configuration = .init()) -> LunaSession {
        LunaSession(configuration: configuration) { "sk-test" }
    }

    @Test("Request targets Luna with a strict schema and an inline image")
    func requestShape() throws {
        let body = session().requestBody(for: .photo(Data([0xFF, 0xD8, 0xFF])))

        #expect(body["model"] as? String == "gpt-5.6-luna")
        #expect((body["reasoning"] as? [String: Any])?["effort"] as? String == "low")

        let format = (body["text"] as? [String: Any])?["format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_schema")
        #expect(format?["name"] as? String == "meal_recognition")
        #expect(format?["strict"] as? Bool == true)

        let input = try #require(body["input"] as? [[String: Any]])
        let userContent = try #require(input.last?["content"] as? [[String: Any]])
        let image = try #require(userContent.first { $0["type"] as? String == "input_image" })
        let url = try #require(image["image_url"] as? String)
        #expect(url.hasPrefix("data:image/jpeg;base64,"))
        #expect(image["detail"] as? String == "low")
    }

    @Test("The schema is valid strict-mode JSON Schema")
    func schemaIsStrictCompliant() throws {
        let schema = MealPrompt.jsonSchema
        #expect(schema["additionalProperties"] as? Bool == false)

        let required = try #require(schema["required"] as? [String])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect(Set(required) == Set(properties.keys), "strict mode requires every property to be listed")

        let dishSchema = try #require(
            ((properties["dishes"] as? [String: Any])?["items"]) as? [String: Any]
        )
        let dishProperties = try #require(dishSchema["properties"] as? [String: Any])
        let itemSchema = try #require(
            ((dishProperties["ingredients"] as? [String: Any])?["items"]) as? [String: Any]
        )
        #expect(itemSchema["additionalProperties"] as? Bool == false)
        #expect(Set(try #require(itemSchema["required"] as? [String])) == [
            "label", "grams", "per_100g", "preparation", "alternatives"
        ])
        // One quantity. `portion` stood beside `grams` until v17 and always lost
        // to it — asking for both spent tokens on an answer nothing read.
        #expect((itemSchema["properties"] as? [String: Any])?["portion"] == nil)

        // Composition is required on every ingredient. With no table behind the
        // app, a missing block is a meal worth zero calories.
        let itemProperties = try #require(itemSchema["properties"] as? [String: Any])
        let composition = try #require(itemProperties["per_100g"] as? [String: Any])
        #expect(Set(try #require(composition["required"] as? [String])) == [
            "protein", "fat", "carbohydrate", "kcal", "sodium_mg"
        ])

        // Uncertainty is a shortlist of rival foods, not a number — and each
        // rival is priced, so choosing one is a local swap.
        let alternatives = try #require(itemProperties["alternatives"] as? [String: Any])
        #expect(alternatives["type"] as? String == "array")
        let alternative = try #require(alternatives["items"] as? [String: Any])
        let alternativeProperties = try #require(alternative["properties"] as? [String: Any])
        #expect(alternativeProperties["per_100g"] != nil)
    }

    @Test("The prompt asks for composition per 100 g, and for one food per label")
    func promptAsksForCompositionPerHundredGrams() {
        let prompt = MealPrompt.system.lowercased()
        // The instruction the whole of v21 rests on. Asked for the figures for
        // the stated weight instead, the app multiplies by the weight twice.
        #expect(prompt.contains("per 100 g of edible portion"))
        #expect(prompt.contains("never for the weight you just reported"))
        #expect(prompt.contains("`sodium_mg` in milligrams"))

        // 18% of the labels v20 could not resolve named two foods. A row that
        // is two foods cannot be priced as either.
        #expect(prompt.contains("it must name exactly one food"))
        #expect(prompt.contains("never \"and\""))

        // Priced as eaten and seasoned — the fix for the salt floor at its
        // source rather than a qualifier on the screen. v24 merged this with
        // the composition-table rule it used to contradict: a table publishes
        // plain preparations, which is exactly what ran 82% low on a canteen
        // bibimbap, and the two bullets stated one after the other left the
        // model to pick.
        #expect(prompt.contains("as it will actually be eaten"))
        #expect(prompt.contains("and seasoned"))

        #expect(prompt.contains("closest place setting"))
        #expect(prompt.contains("`alternatives`"))
        #expect(prompt.contains("empty is normal"))
        #expect(!prompt.contains("confidence"))

        // It names food without turning the recognition response into a health
        // verdict. "Healthy" and "balanced" are verdicts too — a model told to
        // look for healthy food finds it.
        for verdict in ["mediterranean", "medas", "adherence", "healthy", "balanced"] {
            #expect(!prompt.contains(verdict), "the prompt still says \(verdict)")
        }

        // The taxonomy is gone. A stale copy of its guidance here would be
        // instructions for a field the schema no longer emits.
        for retired in ["`kind`", "composition_hints", "other_meals_visible", "sauce_condiment"] {
            #expect(!prompt.contains(retired.lowercased()), "the prompt still says \(retired)")
        }
    }

    @Test("A well-formed response decodes")
    func parsesSuccess() throws {
        let json = """
        {"status":"completed","output":[
          {"type":"reasoning","summary":[]},
          {"type":"message","content":[{"type":"output_text","text":
            "{\\"dishes\\":[{\\"name\\":\\"sardines\\",\\"count\\":1,\\"panel\\":null,\\"ingredients\\":[{\\"grams\\":180,\\"label\\":\\"grilled sardines\\",\\"per_100g\\":{\\"protein\\":24.6,\\"fat\\":11.5,\\"carbohydrate\\":0,\\"kcal\\":208,\\"sodium_mg\\":307},\\"preparation\\":[\\"grilled\\"],\\"alternatives\\":[{\\"label\\":\\"grilled mackerel\\",\\"per_100g\\":{\\"protein\\":23.9,\\"fat\\":17.8,\\"carbohydrate\\":0,\\"kcal\\":262,\\"sodium_mg\\":83}}]},{\\"grams\\":9,\\"label\\":\\"cooking oil\\",\\"per_100g\\":{\\"protein\\":0,\\"fat\\":100,\\"carbohydrate\\":0,\\"kcal\\":884,\\"sodium_mg\\":0},\\"preparation\\":[],\\"alternatives\\":[]}]}]}"
          }]}
        ]}
        """
        let artifact = try LunaSession.parse(Data(json.utf8), promptVersion: "test-v21")
        let recognition = artifact.recognition
        let ingredients = try #require(recognition.dishes.first?.ingredients)
        #expect(ingredients.count == 2)
        #expect(ingredients[0].label == "grilled sardines")
        #expect(ingredients[0].grams == 180)
        #expect(ingredients[0].per100g.protein == 24.6)
        #expect(ingredients[0].alternatives.first?.label == "grilled mackerel")
        #expect(ingredients[1].alternatives.isEmpty)
        #expect(artifact.promptVersion == "test-v21")
        #expect(artifact.rawModelJSON.contains("grilled sardines"))

        let dishes = recognition.asMealDishes()
        let items = dishes.flatMap(\.items)
        #expect(items.count == 2)
        #expect(items[0].label == "grilled sardines")
        #expect(items[0].grams == 180)
        // 180 g at 208 kcal per 100 g. The only arithmetic left in the app.
        #expect(abs(items[0].nutrients.kcal - 374.4) < 0.001)
        #expect(items[0].provenance.kcal == .model)
    }

    @Test("A response with no composition is an error, not a meal worth nothing")
    func rejectsMissingComposition() {
        // The v16 `grams` failure, one field over: with no table behind the app
        // a silently absent `per_100g` would decode to zero calories and look
        // exactly like a light meal.
        let json = """
        {"status":"completed","output":[
          {"type":"message","content":[{"type":"output_text","text":
            "{\\"dishes\\":[{\\"name\\":\\"sardines\\",\\"count\\":1,\\"panel\\":null,\\"ingredients\\":[{\\"grams\\":180,\\"label\\":\\"grilled sardines\\",\\"preparation\\":[],\\"alternatives\\":[]}]}]}"
          }]}
        ]}
        """
        #expect(throws: (any Error).self) {
            try LunaSession.parse(Data(json.utf8), promptVersion: "test-v21")
        }
    }

    @Test("A refusal is surfaced, not decoded into an empty meal")
    func parsesRefusal() {
        let json = """
        {"status":"completed","output":[{"type":"message","content":[
          {"type":"refusal","refusal":"I can't help with that."}]}]}
        """
        #expect(throws: MealRecognizerError.self) { try LunaSession.parse(Data(json.utf8)) }
    }

    @Test("A truncated response is an error, not a partial meal")
    func parsesIncomplete() {
        let json = """
        {"status":"incomplete","incomplete_details":{"reason":"max_output_tokens"},"output":[]}
        """
        #expect(throws: MealRecognizerError.self) { try LunaSession.parse(Data(json.utf8)) }
    }

    @Test("A missing API key fails before any network call")
    func missingKey() async {
        let noKey = LunaSession { nil }
        await #expect(throws: MealRecognizerError.self) {
            try await noKey.recognize(.photo(Data([0x01])))
        }
    }

    @Test("Identical photos are recognized once")
    func cacheAvoidsDuplicateCalls() async throws {
        actor Counter {
            var calls = 0
            func increment() { calls += 1 }
        }
        struct Stub: MealRecognizer {
            let counter: Counter
            func recognize(_ message: MealMessage) async throws -> RecognitionArtifact {
                await counter.increment()
                let recognition = MealRecognition(dishes: [
                    .init(
                        name: "salad",
                        ingredients: [
                            .init(label: "salad", grams: 90, per100g: Fixture.composition)
                        ]
                    )
                ])
                return RecognitionArtifact(
                    recognition: recognition,
                    rawModelJSON: "{\"stub\":true}",
                    promptVersion: "test"
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
        _ = try await caching.recognize(.photo(Data("a different photo".utf8)))

        #expect(await counter.calls == 2)
    }

    @Test("The digest is a stable SHA-256")
    func digestIsStable() {
        #expect(ImageDigest.sha256(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
