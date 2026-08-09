import Foundation

/// The app-owned recognition boundary.
///
/// A request first lands in private R2, then the Worker sends those exact bytes
/// to the configured model. The phone never holds a model-provider credential:
/// the shared token says the caller is the app, and the device id selects the
/// account that owns and can erase the object.
public struct BackendSession: MealRecognizer, MealRefiner, Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var token: String
        public var deviceID: String
        public var provider: RecognitionProvider?
        public var timeout: TimeInterval

        public init(
            baseURL: URL,
            token: String,
            deviceID: String,
            provider: RecognitionProvider? = nil,
            timeout: TimeInterval = 60
        ) {
            self.baseURL = baseURL
            self.token = token
            self.deviceID = deviceID
            self.provider = provider
            self.timeout = timeout
        }
    }

    private let configuration: Configuration
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(configuration: Configuration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    /// Words, a photograph, or both.
    ///
    /// The three image fields travel together or not at all — a `photoHash` with
    /// no bytes fails the server's own integrity check, which compares the two.
    /// The words go up as `said` rather than as the old `note`: the server is
    /// what decides whether they are a caption on a picture or the entire
    /// account of a meal, and it can only decide that if it knows which it got.
    public func recognize(_ message: MealMessage) async throws -> RecognitionArtifact {
        guard !message.isEmpty else { throw MealRecognizerError.emptyMessage }
        let input = RecognitionRequest(
            provider: configuration.provider?.rawValue,
            photoHash: message.imageData.map { ImageDigest.sha256($0) },
            mimeType: message.imageData == nil ? nil : message.mimeType,
            imageBase64: message.imageData?.base64EncodedString(),
            said: message.trimmedText
        )
        let envelope: RecognitionEnvelope = try await send(
            path: "recognitions",
            method: "POST",
            body: input
        )
        return RecognitionArtifact(
            recognition: envelope.recognition,
            rawModelJSON: envelope.rawModelJSON,
            promptVersion: envelope.promptVersion
        )
    }

    /// A correction in the person's own words, with or without a photograph.
    ///
    /// The photo path names the stored model input so the model sees the plate
    /// it read; without one — a meal typed in by hand, or a reading that never
    /// succeeded — the same prompt runs on the list and the words alone. Same
    /// delta contract either way, so the caller cannot tell them apart.
    public func refine(
        imageData: Data?,
        mimeType: String,
        current: [MealItem],
        note: String
    ) async throws -> MealRevision {
        let input = RefinementRequest(
            provider: configuration.provider?.rawValue,
            current: current.map { .init(group: $0.group, grams: $0.grams, label: $0.label) },
            note: note
        )
        let path = imageData
            .map { "recognitions/\(ImageDigest.sha256($0))/refine" } ?? "refinements"
        let envelope: RevisionEnvelope = try await send(path: path, method: "POST", body: input)
        return envelope.revision
    }

    /// Idempotently project local meal events into the backend. Sending the
    /// whole local meal history at launch repairs any write that previously
    /// lost its network race; batches stay within the Worker's 500-event cap.
    public func syncMealEvents(_ events: [LoggedEvent]) async throws {
        let meals = events.filter(\.payload.isMealEvent)
        for start in stride(from: 0, to: meals.count, by: 500) {
            let end = min(start + 500, meals.count)
            let batch = EventBatch(deviceId: configuration.deviceID, events: Array(meals[start..<end]))
            let _: SyncEnvelope = try await send(path: "events/batch", method: "POST", body: batch)
        }
    }

    /// A short-lived Soniox key, minted by the Worker.
    ///
    /// The phone never holds the real one. This is single-use and expires in
    /// minutes, so a key lifted off a device is worth one dictation rather than
    /// an account — which is the only reason live transcription can talk to the
    /// vendor directly instead of streaming audio through our own server.
    public func voiceKey() async throws -> VoiceKey {
        try await send(path: "voice/key", method: "POST", body: EmptyBody())
    }

    /// The Worker re-spells Soniox's `api_key`/`expires_at` in this API's own
    /// camelCase before it reaches the phone, so no vendor's field naming leaks
    /// into the client.
    public struct VoiceKey: Decodable, Sendable {
        public let apiKey: String
        /// ISO-8601, as the vendor writes it. Carried through untouched: a key
        /// is only ever used immediately, so parsing it here would be a date
        /// format to keep in step for no benefit.
        public let expiresAt: String?
    }

    public func deleteAccountData() async throws {
        let _: DeleteEnvelope = try await send(path: "account", method: "DELETE", body: EmptyBody())
    }

    private func send<Body: Encodable, Output: Decodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Output {
        let endpoint = configuration.baseURL.appending(path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        request.setValue("Bearer \(configuration.token)", forHTTPHeaderField: "Authorization")
        request.setValue(configuration.deviceID, forHTTPHeaderField: "X-Device-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "DELETE" { request.httpBody = try encoder.encode(body) }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw BackendError.http(status: http.statusCode, message: message)
        }
        do {
            return try decoder.decode(Output.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }

    private struct RecognitionRequest: Encodable {
        let provider: String?
        /// All three absent together on a message with no photograph. Swift
        /// omits a nil rather than encoding null, which is what the server's
        /// optional fields expect.
        let photoHash: String?
        let mimeType: String?
        let imageBase64: String?
        /// What the person typed or dictated.
        let said: String?
    }

    private struct RefinementRequest: Encodable {
        struct Item: Encodable {
            let group: FoodGroup
            /// Nil for a meal logged before weights, or typed in by hand. Sent
            /// as null rather than filled in: the prompt says "no weight
            /// recorded" in words, and a model told a hand-typed row weighs 100 g
            /// has been handed a fact nobody established.
            let grams: Double?
            let label: String?
        }
        let provider: String?
        let current: [Item]
        let note: String
    }

    private struct RecognitionEnvelope: Decodable {
        let recognition: MealRecognition
        let rawModelJSON: String
        let promptVersion: String
    }
    private struct RevisionEnvelope: Decodable { let revision: MealRevision }
    private struct EventBatch: Encodable { let deviceId: String; let events: [LoggedEvent] }
    private struct SyncEnvelope: Decodable { let accepted: Int; let inserted: Int; let replayed: Int }
    private struct DeleteEnvelope: Decodable {
        let mediaObjects: Int
        let corpusItems: Int
        let corpusObjects: Int
    }
    private struct ErrorEnvelope: Decodable { let error: String }
    private struct EmptyBody: Encodable {}
}

public enum BackendError: Error, LocalizedError, Sendable {
    case invalidRequest(String)
    case emptyResponse
    case http(status: Int, message: String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): message
        case .emptyResponse: "The eatsome service returned no response."
        case .http(_, let message): message
        case .decoding(let detail): "Could not read the eatsome service response: \(detail)"
        }
    }
}

private extension EventPayload {
    var isMealEvent: Bool {
        switch self {
        case .mealLogged, .mealRevised, .mealDeleted: true
        default: false
        }
    }
}
