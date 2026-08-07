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
        let body = session().requestBody(imageData: Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg")

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

        let itemSchema = try #require(
            ((properties["items"] as? [String: Any])?["items"]) as? [String: Any]
        )
        #expect(itemSchema["additionalProperties"] as? Bool == false)
        #expect(Set(try #require(itemSchema["required"] as? [String])) == ["group", "grams", "label", "alternatives"])
        // One quantity. `portion` stood beside `grams` until v17 and always lost
        // to it — asking for both spent tokens on an answer nothing read.
        #expect(itemSchema.description.contains("portion") == false)

        // The enum has to be the actual model, or the app silently drops groups.
        let itemProperties = try #require(itemSchema["properties"] as? [String: Any])
        let groups = try #require((itemProperties["group"] as? [String: Any])?["enum"] as? [String])
        #expect(Set(groups) == Set(FoodGroup.allCases.map(\.rawValue)))

        // Uncertainty is a shortlist of rival groups, not a number.
        let alternatives = try #require(itemProperties["alternatives"] as? [String: Any])
        #expect(alternatives["type"] as? String == "array")
        let alternativeGroups = try #require(
            (alternatives["items"] as? [String: Any])?["enum"] as? [String]
        )
        #expect(Set(alternativeGroups) == Set(FoodGroup.allCases.map(\.rawValue)))
    }

    @Test("The prompt never asks for calories")
    func promptDoesNotRequestCalories() {
        let prompt = MealPrompt.system.lowercased()
        #expect(prompt.contains("never estimate calories"))
        #expect(prompt.contains("closest to the camera"))
        #expect(prompt.contains("other_meals_visible"))
        #expect(prompt.contains("soups"))
        #expect(prompt.contains("miso soup contains legumes"))
        #expect(prompt.contains("`alternatives`"))
        #expect(prompt.contains("an empty list is the"))
        #expect(prompt.contains("never leave it to the user"))
        #expect(!prompt.contains("confidence"))

        // The failures that survived the first field test: skipped sauces,
        // avocado filed as produce, and hedging smuggled into the label.
        #expect(prompt.contains("mayonnaise"))
        #expect(prompt.contains("dressings"))
        #expect(prompt.contains("`healthy_fats`, never fruit or"))
        #expect(prompt.contains("alcohol-free beer"))
        #expect(prompt.contains("is not a label"))
        #expect(!MealPrompt.jsonSchema.description.lowercased().contains("calorie"))
    }


    @Test("The generated prompt matches the file it came from")
    func promptMatchesItsSource() throws {
        // The app, the proxy and the eval harness all read prompts/meal-v5.md.
        // Two copies of a prompt is how a pipeline ends up measuring one thing
        // and shipping another, so a copy that falls behind fails here.
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("prompts/meal-v17.md")
        let source = try String(contentsOf: file, encoding: .utf8)

        #expect(
            MealPrompt.system == source.trimmingCharacters(in: .whitespacesAndNewlines),
            "run: node scripts/sync-prompt.mjs"
        )
        #expect(MealPrompt.version == "meal-v17-2026-08-07")
    }

    @Test("A well-formed response decodes")
    func parsesSuccess() throws {
        let json = """
        {"status":"completed","output":[
          {"type":"reasoning","summary":[]},
          {"type":"message","content":[{"type":"output_text","text":
            "{\\"items\\":[{\\"group\\":\\"fish\\",\\"grams\\":180,\\"label\\":\\"grilled sardines\\",\\"alternatives\\":[\\"white_meat\\"]},{\\"group\\":\\"olive_oil\\",\\"grams\\":9,\\"label\\":null,\\"alternatives\\":[]}],\\"other_meals_visible\\":true,\\"notes\\":null}"
          }]}
        ]}
        """
        let artifact = try LunaSession.parse(Data(json.utf8), promptVersion: "test-v17")
        let recognition = artifact.recognition
        #expect(recognition.items.count == 2)
        #expect(recognition.items[0].group == .fish)
        #expect(recognition.items[0].grams == 180)
        #expect(recognition.items[0].alternatives == [.whiteMeat])
        #expect(recognition.items[1].group == .oliveOil)
        #expect(recognition.items[1].alternatives.isEmpty)
        #expect(recognition.otherMealsVisible)
        #expect(artifact.promptVersion == "test-v17")
        #expect(artifact.rawModelJSON.contains("grilled sardines"))

        let mealItems = recognition.asMealItems()
        #expect(mealItems.count == 2)
        #expect(mealItems[0].label == "grilled sardines")
        #expect(mealItems[0].grams == 180)
        #expect(mealItems[0].modelAlternatives == [.whiteMeat])
    }

    @Test("An answer cached under an older prompt still scores what it scored")
    func parsesPreGramsAnswer() throws {
        // v16 and earlier returned a portion and no weight. Those cache files
        // outlive the prompt that bought them, and throwing them away would cost
        // a real API call each — so the portion is decoded into `servings`,
        // which is where the ladder's answer already lived.
        let json = """
        {"status":"completed","output":[
          {"type":"message","content":[{"type":"output_text","text":
            "{\\"items\\":[{\\"group\\":\\"fish\\",\\"portion\\":\\"large\\",\\"label\\":\\"sardines\\",\\"alternatives\\":[]}],\\"other_meals_visible\\":false,\\"notes\\":null}"
          }]}
        ]}
        """
        let recognition = try LunaSession.parse(Data(json.utf8), promptVersion: "meal-v16").recognition
        #expect(recognition.items[0].grams == nil)
        #expect(recognition.items[0].servings == Portion.large.servings)
        #expect(recognition.asMealItems()[0].effectiveServings() == Portion.large.servings)
    }

    @Test("Only alternatives that would move the score are worth confirming")
    func scoreCriticalAlternatives() {
        let meat = MealRecognition.Item(
            group: .whiteMeat, label: "minced meat topping",
            alternatives: [.redMeat, .processedMeat]
        )
        // Red and processed meat both count against item 5; white meat counts
        // against nothing. Both rivals change the week.
        #expect(meat.scoreCriticalAlternatives() == [.redMeat, .processedMeat])

        let rice = MealRecognition.Item(
            group: .refinedGrains, label: "white rice",
            alternatives: [.wholeGrains]
        )
        // MEDAS scores no grain item at all, so this one is not worth a tap.
        #expect(rice.scoreCriticalAlternatives().isEmpty)

        #expect(Medas.choiceChangesScore(.fish, .whiteMeat))
        #expect(Medas.choiceChangesScore(.oliveOil, .butter))
        #expect(!Medas.choiceChangesScore(.redMeat, .processedMeat))
        #expect(!Medas.choiceChangesScore(.sweets, .pastry))
        #expect(!Medas.choiceChangesScore(.fish, .fish))
    }

    @Test("Legacy confidence caches become the rivals the model never named")
    func parsesLegacyRecognitionCache() throws {
        let legacy = Data(
            #"{"items":[{"group":"white_meat","portion":"medium","label":"minced meat"}],"confidence":0.56,"notes":null}"#.utf8
        )
        let recognition = try JSONDecoder().decode(MealRecognition.self, from: legacy)

        // 0.56 meant "unsure", so the groups white meat is habitually confused
        // with stand in for a shortlist that build never asked for.
        #expect(recognition.items.first?.alternatives == [.fish, .redMeat])
        #expect(recognition.otherMealsVisible == false)

        let confident = Data(
            #"{"items":[{"group":"vegetables","portion":"small","label":"salad","confidence":0.93}],"notes":null}"#.utf8
        )
        #expect(try JSONDecoder().decode(MealRecognition.self, from: confident).items.first?.alternatives.isEmpty == true)
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
            try await noKey.recognize(imageData: Data([0x01]), mimeType: "image/jpeg")
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
            func recognize(imageData: Data, mimeType: String, note: String?) async throws -> RecognitionArtifact {
                await counter.increment()
                let recognition = MealRecognition(
                    items: [.init(
                        group: .vegetables,
                        label: "salad",
                        alternatives: [],
                        grams: 90
                    )],
                    otherMealsVisible: false,
                    notes: nil
                )
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

        _ = try await caching.recognize(imageData: photo, mimeType: "image/jpeg")
        _ = try await caching.recognize(imageData: photo, mimeType: "image/jpeg")
        _ = try await caching.recognize(imageData: Data("a different photo".utf8), mimeType: "image/jpeg")

        #expect(await counter.calls == 2)
    }

    @Test("The digest is a stable SHA-256")
    func digestIsStable() {
        #expect(ImageDigest.sha256(Data("abc".utf8))
            == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
