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
        #expect(Set(try #require(itemSchema["required"] as? [String])) == ["group", "portion", "label"])

        // The enum has to be the actual model, or the app silently drops groups.
        let groups = try #require(
            ((itemSchema["properties"] as? [String: Any])?["group"] as? [String: Any])?["enum"] as? [String]
        )
        #expect(Set(groups) == Set(FoodGroup.allCases.map(\.rawValue)))
    }

    @Test("The prompt never asks for calories")
    func promptDoesNotRequestCalories() {
        let prompt = MealPrompt.system.lowercased()
        #expect(prompt.contains("never estimate calories"))
        #expect(!MealPrompt.jsonSchema.description.lowercased().contains("calorie"))
    }

    @Test("A well-formed response decodes")
    func parsesSuccess() throws {
        let json = """
        {"status":"completed","output":[
          {"type":"reasoning","summary":[]},
          {"type":"message","content":[{"type":"output_text","text":
            "{\\"items\\":[{\\"group\\":\\"fish\\",\\"portion\\":\\"large\\",\\"label\\":\\"grilled sardines\\"},{\\"group\\":\\"olive_oil\\",\\"portion\\":\\"small\\",\\"label\\":null}],\\"confidence\\":0.78,\\"notes\\":null}"
          }]}
        ]}
        """
        let recognition = try LunaSession.parse(Data(json.utf8))
        #expect(recognition.items.count == 2)
        #expect(recognition.items[0].group == .fish)
        #expect(recognition.items[0].portion == .large)
        #expect(recognition.items[1].group == .oliveOil)
        #expect(abs(recognition.confidence - 0.78) < 1e-9)

        let mealItems = recognition.asMealItems()
        #expect(mealItems.count == 2)
        #expect(mealItems[0].label == "grilled sardines")
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
            func recognize(imageData: Data, mimeType: String) async throws -> MealRecognition {
                await counter.increment()
                return MealRecognition(
                    items: [.init(group: .vegetables, portion: .medium, label: "salad")],
                    confidence: 0.9, notes: nil
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
