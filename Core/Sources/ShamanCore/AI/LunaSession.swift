import Foundation

/// OpenAI `gpt-5.6-luna` over the Responses API.
///
/// Chosen because this workload is high-volume, latency-sensitive classification
/// with a fixed output shape — exactly what Luna's tier is for. At $0.20/$1.20
/// per million tokens with a low-detail image, a year of personal logging costs
/// less than a coffee.
///
/// Everything OpenAI-shaped is confined to this file. The app talks to
/// `MealRecognizer`, so moving to a proxy — or to a different provider — is a
/// new conformance, not a refactor.
public struct LunaSession: MealRecognizer {
    public struct Configuration: Sendable {
        public var model: String
        public var endpoint: URL
        /// `low` is the right default: classifying a plate is not a reasoning
        /// problem, and thinking tokens are billed at the output rate.
        public var reasoningEffort: String?
        /// `low` sends a downscaled image. Food groups survive it; raise to
        /// `high` only if you find portion calls degrading.
        public var imageDetail: String
        public var timeout: TimeInterval

        public init(
            model: String = "gpt-5.6-luna",
            endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
            reasoningEffort: String? = "low",
            imageDetail: String = "low",
            timeout: TimeInterval = 45
        ) {
            self.model = model
            self.endpoint = endpoint
            self.reasoningEffort = reasoningEffort
            self.imageDetail = imageDetail
            self.timeout = timeout
        }
    }

    public typealias APIKeyProvider = @Sendable () throws -> String?

    private let configuration: Configuration
    private let apiKey: APIKeyProvider
    private let session: URLSession

    public init(
        configuration: Configuration = .init(),
        session: URLSession = .shared,
        apiKey: @escaping APIKeyProvider
    ) {
        self.configuration = configuration
        self.session = session
        self.apiKey = apiKey
    }

    public func recognize(imageData: Data, mimeType: String) async throws -> MealRecognition {
        guard let key = try apiKey(), !key.isEmpty else { throw MealRecognizerError.missingAPIKey }

        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(imageData: imageData, mimeType: mimeType)
        )

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw MealRecognizerError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw MealRecognizerError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }

        return try Self.parse(data)
    }

    func requestBody(imageData: Data, mimeType: String) -> [String: Any] {
        let dataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"

        var body: [String: Any] = [
            "model": configuration.model,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": MealPrompt.system]]
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": MealPrompt.user],
                        ["type": "input_image", "image_url": dataURL, "detail": configuration.imageDetail]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "meal_recognition",
                    "strict": true,
                    "schema": MealPrompt.jsonSchema
                ]
            ]
        ]
        if let effort = configuration.reasoningEffort {
            body["reasoning"] = ["effort": effort]
        }
        return body
    }

    // MARK: - Response parsing

    private struct Envelope: Decodable {
        struct Output: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
                let refusal: String?
            }
            let type: String
            let content: [Content]?
        }
        struct Incomplete: Decodable { let reason: String? }
        let status: String?
        let output: [Output]?
        let incomplete_details: Incomplete?
    }

    static func parse(_ data: Data) throws -> MealRecognition {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw MealRecognizerError.decoding(String(describing: error))
        }

        // The output array interleaves reasoning items with the message; take
        // the first output_text and ignore the rest.
        let contents = (envelope.output ?? []).filter { $0.type == "message" }.flatMap { $0.content ?? [] }

        if let refusal = contents.first(where: { $0.type == "refusal" })?.refusal {
            throw MealRecognizerError.refused(refusal)
        }

        guard let json = contents.first(where: { $0.type == "output_text" })?.text else {
            if envelope.status == "incomplete" {
                throw MealRecognizerError.incomplete(reason: envelope.incomplete_details?.reason ?? "unknown")
            }
            throw MealRecognizerError.emptyResponse
        }

        do {
            return try JSONDecoder().decode(MealRecognition.self, from: Data(json.utf8))
        } catch {
            throw MealRecognizerError.decoding(String(describing: error))
        }
    }

    private static func errorMessage(from data: Data) -> String {
        struct ErrorEnvelope: Decodable {
            struct Payload: Decodable { let message: String? }
            let error: Payload?
        }
        if let decoded = try? JSONDecoder().decode(ErrorEnvelope.self, from: data),
           let message = decoded.error?.message {
            return message
        }
        return String(data: data, encoding: .utf8) ?? "no body"
    }
}
