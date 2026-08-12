import Foundation

/// The app-owned recognition boundary.
///
/// A request first lands in private R2, then the Worker sends those exact bytes
/// to the configured model. The phone never holds a model-provider credential:
/// the account session proves who the caller is, and the device id preserves
/// the source partition adopted during the first sign-in.
public struct BackendSession: MealRecognizer, MealRefiner, Sendable {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var deviceID: String
        /// Sent as the bearer credential on every authenticated request. Nil is
        /// valid only while exchanging an Apple identity token for a session.
        public var sessionToken: String?
        public var provider: RecognitionProvider?
        public var timeout: TimeInterval

        public init(
            baseURL: URL,
            deviceID: String,
            sessionToken: String? = nil,
            provider: RecognitionProvider? = nil,
            timeout: TimeInterval = 60
        ) {
            self.baseURL = baseURL
            self.deviceID = deviceID
            self.sessionToken = sessionToken
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
            current: current.map { .init(label: $0.label, grams: $0.grams) },
            note: note
        )
        let path = imageData
            .map { "recognitions/\(ImageDigest.sha256($0))/refine" } ?? "refinements"
        let envelope: RevisionEnvelope = try await send(path: path, method: "POST", body: input)
        return envelope.revision
    }

    /// Idempotently copy the local append-only log into the backend. Sending the
    /// whole history at launch repairs any write that previously
    /// lost its network race; batches stay within the Worker's 500-event cap.
    public func syncEvents(_ events: [LoggedEvent]) async throws {
        for start in stride(from: 0, to: events.count, by: 500) {
            let end = min(start + 500, events.count)
            let batch = EventBatch(
                deviceId: configuration.deviceID,
                events: events[start..<end].map(EventInput.init)
            )
            let _: SyncEnvelope = try await send(path: "events/batch", method: "POST", body: batch)
        }
    }

    /// Pull the account union, following the Worker's stable `(recordedAt,id)`
    /// cursor until the final short page. Unknown fields such as
    /// `sourceDeviceId` are deliberately ignored by `LoggedEvent` decoding.
    public func events() async throws -> [LoggedEvent] {
        var result: [LoggedEvent] = []
        var cursor: String?
        while true {
            var query = [URLQueryItem(name: "limit", value: "500")]
            if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
            let page: EventListEnvelope = try await get(path: "events", query: query)
            result.append(contentsOf: page.events)
            guard page.events.count == 500,
                  let next = page.nextCursor,
                  next != cursor
            else { return result }
            cursor = next
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

    /// Trade a provider's identity token for a session, and hand this device's
    /// anonymous history to the account behind it.
    ///
    /// The `nonce` is the *raw* value this sign-in generated, never the hash
    /// that went to Apple. The server does the hashing and compares, so a
    /// client that sends the hash by mistake fails rather than passing a check
    /// that was doing nothing.
    ///
    /// One thing here is permanent: if `merge.adopted` comes back true, this
    /// device's pre-sign-in meals now belong to that account and there is no
    /// way to take them back. A `conflict` means the phone had already been
    /// claimed by a different account — nothing moved, and the old history is
    /// still where it was rather than silently gone.
    public func signIn(
        provider: IdentityProvider,
        identityToken: String,
        nonce: String?
    ) async throws -> SignInResult {
        try await send(
            path: "auth/sessions",
            method: "POST",
            body: SignInBody(
                provider: provider.rawValue,
                identityToken: identityToken,
                nonce: nonce
            ),
            includeSession: false
        )
    }

    /// Sign this device out. Not an un-merge: the adopted history stays with
    /// the account, because signing out of a phone is not asking for that.
    public func signOut() async throws {
        let _: SignOutEnvelope = try await send(
            path: "auth/sessions",
            method: "DELETE",
            body: EmptyBody()
        )
    }

    public func deleteAccountData() async throws {
        let _: DeleteEnvelope = try await send(path: "account", method: "DELETE", body: EmptyBody())
    }

    // MARK: - Tables

    /// Every table you are in, with its badge.
    ///
    /// `since` is the caller's own local start-of-day in epoch millis, because
    /// the server has no idea where this phone's midnight is — the same reason
    /// the server has no reliable local-day boundary. Omit it and
    /// `cookedToday` comes back nil rather than counted against a UTC day
    /// nobody lives in.
    public func tables(since: EpochMillis? = nil) async throws -> TablesListResponse {
        try await get(path: "tables", query: since.map { [URLQueryItem(name: "since", value: "\($0)")] } ?? [])
    }

    public func feed(
        tableID: String,
        cursor: Int? = nil,
        limit: Int? = nil
    ) async throws -> TableFeedResponse {
        var query: [URLQueryItem] = []
        if let cursor { query.append(URLQueryItem(name: "cursor", value: "\(cursor)")) }
        if let limit { query.append(URLQueryItem(name: "limit", value: "\(limit)")) }
        return try await get(path: "tables/\(tableID)/feed", query: query)
    }

    public func createTable(_ request: CreateTableRequest) async throws -> TableSummary {
        do {
            return try await send(path: "tables", method: "POST", body: request)
        } catch BackendError.http(let status, _) where status == 400 {
            // Rolling deployment safety: the previous API used a strict object
            // and rejects the new visibility field. Retrying the same UUID with
            // its legacy shape keeps Create working on a phone installed before
            // the Worker update; the current API accepts only the first call.
            struct LegacyRequest: Encodable {
                let id: String
                let name: String
                let displayName: String
            }
            return try await send(
                path: "tables",
                method: "POST",
                body: LegacyRequest(id: request.id, name: request.name, displayName: request.displayName)
            )
        }
    }

    public func joinTable(_ request: JoinTableRequest) async throws -> TableSummary {
        try await send(path: "tables/join", method: "POST", body: request)
    }

    public func rotateTableInvite(
        tableID: String
    ) async throws -> (inviteCode: String, inviteExpiresAt: EpochMillis?) {
        struct Response: Decodable {
            let inviteCode: String
            let inviteExpiresAt: EpochMillis?
        }
        let response: Response = try await send(
            path: "tables/\(tableID)/invite",
            method: "POST",
            body: EmptyBody()
        )
        return (response.inviteCode, response.inviteExpiresAt)
    }

    public func post(_ request: CreatePostRequest, to tableID: String) async throws -> TablePost {
        try await send(path: "tables/\(tableID)/posts", method: "POST", body: request)
    }

    public func updateTableNote(
        postID: String,
        note: String?,
        in tableID: String
    ) async throws -> String? {
        struct Body: Encodable { let note: String? }
        struct Response: Decodable { let note: String? }
        let response: Response = try await send(
            path: "tables/\(tableID)/posts/\(postID)/note",
            method: "PUT",
            body: Body(note: note)
        )
        return response.note
    }

    /// Idempotent both ways, which is what makes it safe to draw the new state
    /// before the call returns and to retry without checking.
    public func react(
        postID: String,
        kind: TableReaction,
        on: Bool,
        in tableID: String
    ) async throws {
        struct Body: Encodable { let postId: String; let kind: String; let on: Bool }
        let _: EmptyResponse = try await send(
            path: "tables/\(tableID)/reactions",
            method: "PUT",
            body: Body(postId: postID, kind: kind.rawValue, on: on)
        )
    }

    /// The top `seq` actually rendered. Monotonic server-side, so a phone that
    /// was offline cannot un-read what another device already saw.
    public func markRead(seq: Int, in tableID: String) async throws {
        struct Body: Encodable { let seq: Int }
        let _: EmptyResponse = try await send(
            path: "tables/\(tableID)/read",
            method: "PUT",
            body: Body(seq: seq)
        )
    }

    /// The bytes of a shared photograph, membership-gated by the server.
    /// `TablePost.hasPhoto` says whether it is worth asking.
    public func tablePhoto(postID: String, in tableID: String) async throws -> Data {
        try await bytes(path: "tables/\(tableID)/media/\(postID)")
    }

    /// A private meal photograph previously uploaded by this account.
    ///
    /// Account history contains hashes rather than image bytes. A fresh install
    /// uses those hashes to rebuild its local photo cache after the event union
    /// has been downloaded. The Worker checks every device partition adopted by
    /// the signed-in account, so photographs made before sign-in are included.
    public func mealPhoto(hash: String) async throws -> Data {
        try await bytes(path: "media/\(hash.lowercased())")
    }

    private struct EmptyResponse: Decodable {
        init(from decoder: any Decoder) throws {}
    }

    private func get<Output: Decodable>(path: String, query: [URLQueryItem] = []) async throws -> Output {
        let data = try await bytes(path: path, query: query)
        do {
            return try decoder.decode(Output.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }

    /// Query items go through `URLComponents` rather than into the path.
    /// `URL.appending(path:)` treats its whole argument as one path component
    /// and percent-encodes the `?`, so a hand-built query string arrives as a
    /// literal path segment — the request succeeds against a route that ignores
    /// it and quietly comes back unfiltered, which for `since` would mean
    /// `cookedToday` counted against nothing at all.
    private func bytes(path: String, query: [URLQueryItem] = []) async throws -> Data {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let endpoint = components?.url else { throw BackendError.emptyResponse }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = configuration.timeout
        request.setValue(configuration.deviceID, forHTTPHeaderField: "X-Device-Id")
        if let session = configuration.sessionToken, !session.isEmpty {
            request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.emptyResponse }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorEnvelope.self, from: data).error)
                ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw BackendError.http(status: http.statusCode, message: message)
        }
        return data
    }

    private func send<Body: Encodable, Output: Decodable>(
        path: String,
        method: String,
        body: Body,
        includeSession: Bool = true
    ) async throws -> Output {
        let endpoint = configuration.baseURL.appending(path: path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeout
        request.setValue(configuration.deviceID, forHTTPHeaderField: "X-Device-Id")
        // Sign-in intentionally omits a stale session so an expired credential
        // cannot prevent recovery. Every other production route requires this
        // account bearer; pinned evaluation deployments accept no bearer.
        if includeSession, let session = configuration.sessionToken, !session.isEmpty {
            request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
        }
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

    private struct SignInBody: Encodable {
        let provider: String
        let identityToken: String
        let nonce: String?
    }
    private struct SignOutEnvelope: Decodable { let revoked: Int }

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
            let label: String
            let grams: Double
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
    /// The list endpoint adds `sourceDeviceId`, but the ingest contract accepts
    /// only the canonical event. Re-uploading a pulled union is safe and
    /// idempotent as long as that read-only provenance field is stripped here.
    private struct EventInput: Encodable {
        let event: LoggedEvent
        init(_ event: LoggedEvent) { self.event = event }

        private enum CodingKeys: String, CodingKey { case id, occurredAt, recordedAt, payload }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(event.id, forKey: .id)
            try container.encode(event.occurredAt, forKey: .occurredAt)
            try container.encode(event.recordedAt, forKey: .recordedAt)
            try container.encode(event.payload, forKey: .payload)
        }
    }
    private struct EventBatch: Encodable { let deviceId: String; let events: [EventInput] }
    private struct SyncEnvelope: Decodable { let accepted: Int; let inserted: Int; let replayed: Int }
    private struct EventListEnvelope: Decodable {
        let events: [LoggedEvent]
        let nextCursor: String?
    }
    private struct DeleteEnvelope: Decodable {
        let mediaObjects: Int
        let corpusItems: Int
        let corpusObjects: Int
    }
    private struct ErrorEnvelope: Decodable { let error: String }
    private struct EmptyBody: Encodable {}
}

public enum IdentityProvider: String, Sendable, CaseIterable {
    case apple
    case google
}

/// What the server says came of a sign-in.
///
/// `merge` is the part worth showing a human. Nothing about this app's history
/// moves — the server reads the union of the partitions an account owns rather
/// than rewriting rows — so `adopted` means "this phone's earlier meals are now
/// also the account's", and `conflict` means the phone was already claimed and
/// they stayed where they were.
public struct SignInResult: Decodable, Sendable {
    public struct Merge: Decodable, Sendable {
        public let partition: String
        public let adopted: Bool
        /// `linked_to_another_account`, or nil. A string rather than an enum:
        /// a server that grows a new reason must not fail to decode on an old
        /// build, and this one is shown, not switched on.
        public let conflict: String?
    }

    public let accountId: String
    public let sessionToken: String
    public let expiresAt: EpochMillis
    public let accountCreated: Bool
    public let merge: Merge
}

/// The client half of the replay check.
///
/// A raw random value stays on the phone and its SHA-256 goes to the provider,
/// which echoes the hash into the identity token. The server hashes the raw
/// value we send it and compares. Sending the raw nonce to the provider instead
/// would work identically and put the secret in one more place for no gain.
public enum SignInNonce {
    public struct Pair: Sendable {
        /// Goes to the server, alongside the identity token.
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
