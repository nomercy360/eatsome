import CryptoKit
import Foundation

public enum ImageDigest {
    /// Content hash of the model-input bytes. Also stored on `MealEntry` as
    /// `photoHash`, so recognition, R2 and the eval rows all name one render.
    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// The app-owned boundary to the Worker.
///
/// The phone never holds a model-provider credential: the account session
/// proves who the caller is, and the device id names the partition its
/// history lives in. Everything here is one of three conversations — ask the
/// model, mirror the log, prove who you are — and each one has one method.
///
/// Two things this type is careful about, both to do with the log:
///
/// - **`syncEvents(_:)` is the only upload path and it takes `[LoggedEvent]`.**
///   That is a type fence, not a convenience. A future phone-only record — a
///   period log, a health import — is a different type, and a different type
///   cannot be passed here by construction. Do not add a second uploader.
/// - **The batch is spliced, never encoded.** A retained event from a newer
///   build (`EventPayload.unrecognized`) is bytes this build cannot make sense
///   of and must not re-serialise; `RawJSON` is bytes and is not `Encodable`.
///   `EventCodec.batch` builds the body byte-for-byte and this type sends it as
///   it is.
public struct BackendSession: Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var deviceID: String
        /// Bearer credential on every authenticated request. Nil is valid only
        /// while exchanging an identity token for a session.
        public var sessionToken: String?
        public var timeout: TimeInterval

        public init(
            baseURL: URL,
            deviceID: String,
            sessionToken: String? = nil,
            timeout: TimeInterval = 60
        ) {
            self.baseURL = baseURL
            self.deviceID = deviceID
            self.sessionToken = sessionToken
            self.timeout = timeout
        }
    }

    /// The Worker's ingest ceiling per request. Larger logs go up in pieces.
    public static let batchSize = 500

    private let configuration: Configuration
    private let session: URLSession
    private let codec: EventCodec
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        configuration: Configuration,
        session: URLSession = .shared,
        codec: EventCodec = EventCodec()
    ) {
        self.configuration = configuration
        self.session = session
        self.codec = codec
    }

    // MARK: - Recognition

    /// What the Worker says one message was.
    public struct Recognition: Sendable {
        public let recognition: MealRecognition
        /// The model's answer verbatim, kept as evidence beside the meal.
        public let rawModelJSON: String
        /// `<prompt>/<model>` — what question produced this answer.
        public let promptVersion: String
        /// The photograph's content hash when there was one; what `MealEntry`
        /// stores and what the Worker keeps the bytes under.
        public let photoHash: String?
        /// True when the Worker answered from its cache rather than the model.
        public let cached: Bool
    }

    /// Words, a photograph, or both.
    ///
    /// The three image fields travel together or not at all — a hash with no
    /// bytes fails the Worker's own integrity check. The words go up as `said`:
    /// the Worker decides whether they caption a picture or are the entire
    /// account of the meal, and it can only decide that if it knows which it
    /// received.
    public func recognize(
        said: String?,
        image: (data: Data, mimeType: String)? = nil
    ) async throws -> Recognition {
        let words = said?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard image != nil || !(words?.isEmpty ?? true) else {
            throw BackendError.invalidRequest("A recognition needs a photograph or a message.")
        }
        let photoHash = image.map { ImageDigest.sha256($0.data) }
        let input = RecognitionRequest(
            photoHash: photoHash,
            mimeType: image?.mimeType,
            imageBase64: image?.data.base64EncodedString(),
            said: (words?.isEmpty ?? true) ? nil : words
        )
        let envelope: RecognitionEnvelope = try await send(
            path: "recognitions",
            method: "POST",
            body: input
        )
        return Recognition(
            recognition: envelope.recognition,
            rawModelJSON: envelope.rawModelJSON,
            promptVersion: envelope.promptVersion,
            photoHash: photoHash,
            cached: envelope.cached ?? false
        )
    }

    // MARK: - Corrections

    /// A correction to a meal, in the person's own words, with or without the
    /// photograph the meal was read from.
    ///
    /// The photo path names the stored model input so the model sees the plate
    /// it read; without one — a meal typed in by hand, or a reading that never
    /// succeeded — the same prompt runs on the list and the words alone. Same
    /// delta contract either way, so the caller cannot tell them apart. The
    /// result restates `per_100g` on everything it moves; apply it with
    /// `MealRevision.applied(to:)`, which stamps the rows `.user`.
    public func refine(
        meal current: [MealDish],
        note: String,
        photoHash: String? = nil
    ) async throws -> MealRevision {
        var nextItem = 1
        let dishes = current.map { dish -> MealRefinementRequest.Dish in
            let indices = Array(nextItem..<(nextItem + dish.items.count))
            nextItem += dish.items.count
            return .init(name: dish.name ?? "Unnamed dish", count: dish.count, itemIndices: indices)
        }
        let input = MealRefinementRequest(
            current: current.flatMap(\.items).map { .init(label: $0.label, grams: $0.grams) },
            dishes: dishes,
            note: note
        )
        let path = photoHash.map { "recognitions/\($0.lowercased())/refine" } ?? "refinements"
        let envelope: MealRevisionEnvelope = try await send(path: path, method: "POST", body: input)
        return envelope.revision
    }


    // MARK: - The log

    /// Idempotently copy events into the Worker's mirror. The one upload path.
    ///
    /// Sending the whole history at launch repairs any write that lost its
    /// network race; batches stay within the Worker's per-request cap. An
    /// event this build cannot read goes up as the bytes it arrived in.
    public func syncEvents(_ events: [LoggedEvent]) async throws {
        for start in stride(from: 0, to: events.count, by: Self.batchSize) {
            let end = min(start + Self.batchSize, events.count)
            let batch = try codec.batch(
                deviceID: configuration.deviceID,
                events: Array(events[start..<end])
            )
            let _: SyncEnvelope = try await send(path: "events/batch", method: "POST", raw: batch)
        }
    }

    /// One page of the account's log as the Worker holds it, from every device
    /// that has ever written to it. Each line comes back exactly as it was
    /// uploaded — a kind this build does not know is still a line it can keep —
    /// and the cursor is opaque: hand it back to get the next page, and stop
    /// when it comes back nil.
    ///
    /// This is the other half of the mirror. Events are immutable and named by
    /// id, so a phone and the Worker converge by union: pull what the phone
    /// lacks, push what the Worker lacks, and neither side ever deletes the
    /// other's rows. A reinstall or a second phone recovers history by pulling;
    /// a deletion is a `mealDeleted` event like any other write.
    public func pullEvents(after cursor: String?, limit: Int = Self.batchSize) async throws -> EventPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor, !cursor.isEmpty { query.append(URLQueryItem(name: "after", value: cursor)) }
        let envelope: PullEnvelope = try decode(
            try await perform(request(path: "events", query: query, method: "GET", includeSession: true))
        )
        let lines = try envelope.events.map { text -> RawJSON in
            do { return try RawJSON(validating: text) } catch {
                throw BackendError.decoding("A pulled event was not one JSON value: \(error)")
            }
        }
        return EventPage(lines: lines, cursor: envelope.cursor)
    }

    public struct EventPage: Sendable {
        /// Log lines, verbatim. Append with `EventLog.append(lines:)`, which
        /// skips ids the phone already holds.
        public let lines: [RawJSON]
        /// Nil when this was the last page.
        public let cursor: String?
    }

    /// A private meal photograph this account uploaded earlier. Local history
    /// holds hashes, not bytes; a reinstall recovers the pictures by hash.
    public func mealPhoto(hash: String) async throws -> Data {
        try await bytes(path: "media/\(hash.lowercased())")
    }

    // MARK: - Account

    /// Trade a provider's identity token for a session, and hand this device's
    /// anonymous history to the account behind it.
    ///
    /// `nonce` is the *raw* value this sign-in generated, never the hash that
    /// went to Apple; the Worker hashes and compares.
    public func signIn(
        provider: IdentityProvider,
        identityToken: String,
        nonce: String?
    ) async throws -> SignInResult {
        try await send(
            path: "auth/sessions",
            method: "POST",
            body: SignInBody(provider: provider.rawValue, identityToken: identityToken, nonce: nonce),
            includeSession: false
        )
    }

    /// Sign this device out.
    public func signOut() async throws {
        let _: SignOutEnvelope = try await send(path: "auth/sessions", method: "DELETE", body: EmptyBody())
    }

    public func deleteAccountData() async throws {
        let _: DeleteEnvelope = try await send(path: "account", method: "DELETE", body: EmptyBody())
    }

    // MARK: - Transport

    private func request(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        includeSession: Bool
    ) -> URLRequest {
        var url = configuration.baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        request.setValue(configuration.deviceID, forHTTPHeaderField: "X-Device-Id")
        // Sign-in omits a stale session so an expired credential cannot
        // prevent recovery. Every other route requires the account bearer.
        if includeSession, let token = configuration.sessionToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw BackendError.http(status: http.statusCode, message: message)
        }
        return data
    }

    private func decode<Output: Decodable>(_ data: Data) throws -> Output {
        do {
            return try decoder.decode(Output.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }

    private func bytes(path: String) async throws -> Data {
        try await perform(request(path: path, method: "GET", includeSession: true))
    }

    private func send<Body: Encodable, Output: Decodable>(
        path: String,
        method: String,
        body: Body,
        includeSession: Bool = true
    ) async throws -> Output {
        var request = request(path: path, method: method, includeSession: includeSession)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if method != "DELETE" { request.httpBody = try encoder.encode(body) }
        return try decode(try await perform(request))
    }

    /// A body that is already bytes. This is how the log goes up: nothing
    /// between `EventCodec.batch` and the wire may re-serialise it.
    private func send<Output: Decodable>(
        path: String,
        method: String,
        raw body: RawJSON
    ) async throws -> Output {
        var request = request(path: path, method: method, includeSession: true)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.bytes
        return try decode(try await perform(request))
    }

    // MARK: - Wire shapes

    private struct RecognitionRequest: Encodable {
        /// All three absent together on a message with no photograph. Swift
        /// omits a nil rather than encoding null, which is what the Worker's
        /// optional fields expect.
        let photoHash: String?
        let mimeType: String?
        let imageBase64: String?
        let said: String?
    }
    private struct RecognitionEnvelope: Decodable {
        let recognition: MealRecognition
        let rawModelJSON: String
        let promptVersion: String
        let cached: Bool?
    }
    private struct MealRefinementRequest: Encodable {
        struct Item: Encodable { let label: String; let grams: Double }
        struct Dish: Encodable {
            let name: String
            let count: Int
            let itemIndices: [Int]
            private enum CodingKeys: String, CodingKey {
                case name, count
                case itemIndices = "item_indices"
            }
        }
        let current: [Item]
        let dishes: [Dish]
        let note: String
    }
    private struct MealRevisionEnvelope: Decodable { let revision: MealRevision }
    private struct SignInBody: Encodable {
        let provider: String
        let identityToken: String
        let nonce: String?
    }
    private struct SignOutEnvelope: Decodable { let revoked: Int }
    private struct SyncEnvelope: Decodable { let accepted: Int; let inserted: Int; let replayed: Int }
    private struct PullEnvelope: Decodable { let events: [String]; let cursor: String? }
    private struct DeleteEnvelope: Decodable {
        let mediaObjects: Int
        let events: Int
    }
    private struct ErrorEnvelope: Decodable { let error: String }
    private struct EmptyBody: Encodable {}
}

/// Sign in with Apple is the only identity. The enum stays because the wire
/// names the provider, and a second one would be a new case here and a new
/// verifier on the Worker, not a new code path on the phone.
public enum IdentityProvider: String, Sendable, CaseIterable {
    case apple
}

/// What the Worker says came of a sign-in.
public struct SignInResult: Decodable, Sendable {
    public let accountId: String
    public let sessionToken: String
    public let expiresAt: EpochMillis
    public let accountCreated: Bool
}

/// The client half of the replay check: a raw random value stays on the phone
/// and its SHA-256 goes to the provider, which echoes it into the identity
/// token. The Worker hashes what we send and compares.
public enum SignInNonce {
    public struct Pair: Sendable {
        /// Goes to the Worker, alongside the identity token.
        public let raw: String
        /// Goes to Apple, in the authorization request.
        public let hashed: String
    }

    public static func generate() -> Pair {
        var bytes = [UInt8](repeating: 0, count: 32)
        for index in bytes.indices { bytes[index] = UInt8.random(in: 0...255) }
        let raw = bytes.map { String(format: "%02x", $0) }.joined()
        return Pair(raw: raw, hashed: ImageDigest.sha256(Data(raw.utf8)))
    }
}

public enum BackendError: Error, LocalizedError, Sendable, Equatable {
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

