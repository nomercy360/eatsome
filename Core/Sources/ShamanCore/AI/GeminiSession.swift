import Foundation

/// Google `gemini-3.6-flash` over the Gemini API's `generateContent` endpoint.
///
/// This exists to be measured, not to be assumed better. Published food-photo
/// benchmarks disagree with each other about which provider wins — one has the
/// Flash tier ahead of every flagship on fine-grained dish classification,
/// another has it losing to the same flagships by a factor of two — which means
/// the benchmark choice decides the answer more than the model choice does. The
/// only number worth acting on is the one your own plates produce, and this file
/// is what makes that measurable: `MealRecognizer` is the seam, and the eval
/// pair records which generator produced each row.
///
/// Everything Gemini-shaped lives here, the same way everything OpenAI-shaped
/// lives in `LunaSession`.
public struct GeminiSession: MealRecognizer, MealRefiner {
    public struct Configuration: Sendable {
        public var model: String
        /// Everything up to `/models` — the version prefix, so a v1 migration is
        /// a config edit.
        public var baseURL: URL
        /// `minimal`, `low`, `medium`, `high`. Classifying a plate is not a
        /// reasoning problem and thinking tokens bill at the output rate.
        public var thinkingLevel: String?
        /// Token budget per image. Left unset by default: the enum spelling
        /// differs between API generations, and an unrecognized value fails the
        /// whole request. Set it from `shaman-config.json` once you have
        /// confirmed the value your endpoint accepts.
        public var mediaResolution: String?
        public var timeout: TimeInterval
        public var systemPrompt: String
        public var promptVersion: String

        public init(
            model: String = "gemini-3.6-flash",
            baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!,
            thinkingLevel: String? = "low",
            mediaResolution: String? = nil,
            timeout: TimeInterval = 45,
            systemPrompt: String = MealPrompt.system,
            promptVersion: String = MealPrompt.version
        ) {
            self.model = model
            self.baseURL = baseURL
            self.thinkingLevel = thinkingLevel
            self.mediaResolution = mediaResolution
            self.timeout = timeout
            self.systemPrompt = systemPrompt
            self.promptVersion = promptVersion
        }

        var endpoint: URL? {
            let escaped = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
            return URL(string: "\(baseURL.absoluteString)/models/\(escaped):generateContent")
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
        self.apiKey = apiKey
        self.session = session
    }

    public func recognize(_ message: MealMessage) async throws -> RecognitionArtifact {
        guard !message.isEmpty else { throw MealRecognizerError.emptyMessage }
        let data = try await post(requestBody(for: message))
        return try Self.parse(data, promptVersion: configuration.promptVersion)
    }

    public func refine(
        imageData: Data?,
        mimeType: String,
        current: [MealItem],
        note: String
    ) async throws -> MealRevision {
        let data = try await post(
            revisionRequestBody(imageData: imageData, mimeType: mimeType, current: current, note: note)
        )
        return try Self.parseRevision(data)
    }

    private func post(_ body: [String: Any]) async throws -> Data {
        guard let key = try apiKey(), !key.isEmpty else { throw MealRecognizerError.missingAPIKey }
        guard let endpoint = configuration.endpoint else {
            throw MealRecognizerError.invalidEndpoint("\(configuration.baseURL) + \(configuration.model)")
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = configuration.timeout
        // The key goes in a header, never the query string: URLs end up in logs.
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw MealRecognizerError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw MealRecognizerError.http(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    func requestBody(for message: MealMessage) -> [String: Any] {
        var generationConfig: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": Self.responseSchema
        ]
        if let level = configuration.thinkingLevel {
            generationConfig["thinkingConfig"] = ["thinkingLevel": level]
        }
        if let resolution = configuration.mediaResolution {
            generationConfig["mediaResolution"] = resolution
        }

        // The image part is omitted entirely when there is none, never sent
        // empty: a zero-length `inlineData` is a decode error at the vendor
        // rather than an absent picture.
        var parts: [[String: Any]] = [["text": MealPrompt.userMessage(for: message)]]
        if let imageData = message.imageData {
            parts.append([
                "inlineData": ["mimeType": message.mimeType, "data": imageData.base64EncodedString()]
            ])
        }

        return [
            "systemInstruction": ["parts": [["text": configuration.systemPrompt]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig
        ]
    }

    func revisionRequestBody(
        imageData: Data?,
        mimeType: String,
        current: [MealItem],
        note: String
    ) -> [String: Any] {
        var parts: [[String: Any]] = [
            ["text": MealRevisionPrompt.message(current: current, note: note)]
        ]
        if let imageData {
            parts.append(["inlineData": ["mimeType": mimeType, "data": imageData.base64EncodedString()]])
        }

        var generationConfig: [String: Any] = [
            "responseMimeType": "application/json",
            "responseSchema": MealRevisionPrompt.geminiResponseSchema
        ]
        if let level = configuration.thinkingLevel {
            generationConfig["thinkingConfig"] = ["thinkingLevel": level]
        }
        if let resolution = configuration.mediaResolution {
            generationConfig["mediaResolution"] = resolution
        }

        return [
            "systemInstruction": ["parts": [["text": MealRevisionPrompt.system]]],
            "contents": [["role": "user", "parts": parts]],
            "generationConfig": generationConfig
        ]
    }

    /// The same contract as `MealPrompt.jsonSchema`, in Gemini's OpenAPI subset.
    ///
    /// It is a subset, not a dialect of the same thing: `additionalProperties`
    /// is not accepted, a nullable field is `nullable: true` rather than a union
    /// type, and `propertyOrdering` is what keeps the emitted keys stable. Type
    /// names are the proto enum spellings, which every API version accepts.
    static var responseSchema: [String: Any] {
        let kind: [String: Any] = ["type": "STRING", "enum": FoodKind.allCases.map(\.rawValue)]
        let ingredient: [String: Any] = [
            "type": "OBJECT",
            "propertyOrdering": [
                "kind", "grams", "label", "preparation", "composition_hints", "alternatives"
            ],
            "required": [
                "kind", "grams", "label", "preparation", "composition_hints", "alternatives"
            ],
            "properties": [
                "kind": kind,
                "grams": ["type": "NUMBER", "description": MealPrompt.gramsDescription],
                "label": ["type": "STRING", "description": "Short, specific food name."],
                "preparation": [
                    "type": "ARRAY",
                    "items": ["type": "STRING", "enum": PreparationMethod.allCases.map(\.rawValue)]
                ],
                "composition_hints": [
                    "type": "ARRAY",
                    "items": ["type": "STRING", "enum": CompositionHint.allCases.map(\.rawValue)]
                ],
                "alternatives": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "propertyOrdering": ["label", "kind"],
                        "required": ["label", "kind"],
                        "properties": ["label": ["type": "STRING"], "kind": kind]
                    ]
                ]
            ]
        ]
        let nullableNumber: [String: Any] = ["type": "NUMBER", "nullable": true]
        let panel: [String: Any] = [
            "type": "OBJECT",
            "nullable": true,
            "propertyOrdering": [
                "protein", "calories", "fat", "carbohydrate", "salt", "sodium",
                "caffeine", "basis", "net_ml", "net_g"
            ],
            "required": [
                "protein", "calories", "fat", "carbohydrate", "salt", "sodium",
                "caffeine", "basis", "net_ml", "net_g"
            ],
            "properties": [
                "protein": nullableNumber, "calories": nullableNumber,
                "fat": nullableNumber, "carbohydrate": nullableNumber,
                "salt": nullableNumber, "sodium": nullableNumber,
                "caffeine": nullableNumber,
                "basis": [
                    "type": "STRING", "nullable": true,
                    "enum": ["per_100ml", "per_100g", "per_serving", "per_container"]
                ],
                "net_ml": nullableNumber, "net_g": nullableNumber
            ]
        ]
        return [
            "type": "OBJECT",
            "propertyOrdering": ["dishes", "other_meals_visible", "notes"],
            "required": ["dishes", "other_meals_visible", "notes"],
            "properties": [
                "dishes": [
                    "type": "ARRAY",
                    "items": [
                        "type": "OBJECT",
                        "propertyOrdering": ["name", "count", "panel", "ingredients"],
                        "required": ["name", "count", "panel", "ingredients"],
                        "properties": [
                            "name": ["type": "STRING"],
                            "count": ["type": "INTEGER"],
                            "panel": panel,
                            "ingredients": ["type": "ARRAY", "items": ingredient]
                        ]
                    ]
                ],
                "other_meals_visible": [
                    "type": "BOOLEAN",
                    "description": "True when food on another tray or place setting was deliberately ignored."
                ],
                "notes": [
                    "type": "STRING",
                    "nullable": true,
                    "description": "Ambiguities worth a human glance. Null if none."
                ]
            ]
        ]
    }

    // MARK: - Response parsing

    private struct Envelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                    /// Thought summaries arrive as ordinary parts with this set.
                    let thought: Bool?
                }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct PromptFeedback: Decodable { let blockReason: String? }
        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }

    static func parse(
        _ data: Data,
        promptVersion: String = MealPrompt.version
    ) throws -> RecognitionArtifact {
        let json = try outputText(data)
        do {
            let recognition = try JSONDecoder().decode(MealRecognition.self, from: Data(json.utf8))
            return RecognitionArtifact(
                recognition: recognition,
                rawModelJSON: json,
                promptVersion: promptVersion
            )
        } catch {
            throw MealRecognizerError.decoding(String(describing: error))
        }
    }

    static func parseRevision(_ data: Data) throws -> MealRevision {
        let json = try outputText(data)
        do {
            return try JSONDecoder().decode(MealRevision.self, from: Data(json.utf8))
        } catch {
            throw MealRecognizerError.decoding(String(describing: error))
        }
    }

    /// The model's JSON out of a `generateContent` envelope, or the matching
    /// error.
    static func outputText(_ data: Data) throws -> String {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw MealRecognizerError.decoding(String(describing: error))
        }

        if let blockReason = envelope.promptFeedback?.blockReason {
            throw MealRecognizerError.refused(blockReason)
        }
        guard let candidate = envelope.candidates?.first else { throw MealRecognizerError.emptyResponse }

        // Anything other than STOP means the answer is partial. A truncated meal
        // that still parses is the worst outcome: it silently drops food.
        if let reason = candidate.finishReason, reason != "STOP" {
            throw MealRecognizerError.incomplete(reason: reason)
        }

        let json = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
        guard !json.isEmpty else { throw MealRecognizerError.emptyResponse }
        return json
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
