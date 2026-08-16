import Foundation
import Testing
@testable import EatsomeCore

/// The session against a stub transport. What these check is the part that
/// would be silent if wrong: that a retained newer-build line reaches the wire
/// byte for byte, that reconciliation refuses corruption and only corruption,
/// and that nothing re-serialises the log on its way out.
@Suite("BackendSession", .serialized)
struct BackendSessionTests {
    static let base = URL(string: "https://api.example.test/v1")!

    static func backend(token: String? = "account-session") -> BackendSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return BackendSession(
            configuration: .init(
                baseURL: base,
                deviceID: "iphone-owner-0001",
                sessionToken: token
            ),
            session: URLSession(configuration: config)
        )
    }

    static func deleted(_ n: Int) -> LoggedEvent {
        LoggedEvent(
            id: UUIDv7.generate(at: 1_700_000_000_000 + EpochMillis(n)),
            occurredAt: EpochMillis(n),
            recordedAt: EpochMillis(n),
            payload: .messageDeleted(messageID: UUIDv7.generate(at: 1_600_000_000_000 + EpochMillis(n)))
        )
    }

    /// A line a build after this one wrote. Every byte-faithfulness trap in it.
    static let futureLine = """
    {"id":"019905a0-2f3a-7c1e-8b6c-0f2c9a1d5e77","occurredAt":1786788000000,"recordedAt":1786788012345,"payload":{"kind":"mood_noted","data":{"z":1.0,"a":9007199254740993,"s":"caf\\u00e9"}}}
    """
    static var future: LoggedEvent {
        get throws { try EventCodec().event(from: RawJSON(validating: futureLine)) }
    }

    static let ok = #"{"accepted":1,"inserted":1,"replayed":0}"#

    // MARK: Upload

    @Test("A newer build's line goes up byte for byte, beside events this build encoded")
    func uploadsRetainedLineVerbatim() async throws {
        let sent = Captured()
        StubURLProtocol.install { request in
            sent.append(request)
            return (200, Data(Self.ok.utf8))
        }
        defer { StubURLProtocol.reset() }

        try await Self.backend().syncEvents([Self.deleted(1), try Self.future])

        let request = try #require(sent.requests.first)
        #expect(request.url?.path == "/v1/events/batch")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer account-session")
        #expect(request.value(forHTTPHeaderField: "X-Device-Id") == "iphone-owner-0001")
        let body = try #require(sent.bodies.first)
        // Verbatim: not `1`, not reordered, not `é`.
        #expect(body.contains(Self.futureLine))
        // And a valid batch around it, of two events.
        let parsed = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        #expect(parsed?["deviceId"] as? String == "iphone-owner-0001")
        #expect((parsed?["events"] as? [Any])?.count == 2)
    }

    @Test("A long log goes up in batches of the Worker's cap, in order")
    func batches() async throws {
        let sent = Captured()
        StubURLProtocol.install { request in
            sent.append(request)
            return (200, Data(Self.ok.utf8))
        }
        defer { StubURLProtocol.reset() }

        try await Self.backend().syncEvents((0..<1_001).map(Self.deleted))

        #expect(sent.requests.count == 3)
        let counts = try sent.bodies.map { body -> Int in
            let parsed = try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
            return (parsed?["events"] as? [Any])?.count ?? -1
        }
        #expect(counts == [500, 500, 1])
    }

    @Test("Nothing goes up when there is nothing")
    func emptyUpload() async throws {
        let sent = Captured()
        StubURLProtocol.install { request in
            sent.append(request)
            return (200, Data(Self.ok.utf8))
        }
        defer { StubURLProtocol.reset() }
        try await Self.backend().syncEvents([])
        #expect(sent.requests.isEmpty)
    }

    // MARK: Pull

    @Test("A pull hands back verbatim lines and the cursor, and stops on nil")
    func pullsVerbatimLines() async throws {
        let sent = Captured()
        StubURLProtocol.install { request in
            sent.append(request)
            let query = request.url?.query ?? ""
            if query.contains("after=") {
                return (200, Data(#"{"events":[],"cursor":null}"#.utf8))
            }
            let page = try! JSONSerialization.data(withJSONObject: ["events": [Self.futureLine], "cursor": "1786788012345:019905a0"])
            return (200, page)
        }
        defer { StubURLProtocol.reset() }

        let first = try await Self.backend().pullEvents(after: nil, limit: 2)
        #expect(first.cursor == "1786788012345:019905a0")
        #expect(first.lines.map(\.text) == [Self.futureLine])
        let second = try await Self.backend().pullEvents(after: first.cursor)
        #expect(second.cursor == nil)
        #expect(second.lines.isEmpty)
        #expect(sent.requests.map { $0.url?.path } == ["/v1/events", "/v1/events"])
        #expect(sent.requests[0].url?.query == "limit=2")
        #expect(sent.requests[1].url?.query == "limit=500&after=1786788012345:019905a0")
    }

    @Test("A pulled element that is not one JSON value is a decoding error, not a corrupt line on disk")
    func pullRefusesGarbage() async throws {
        StubURLProtocol.install { _ in
            (200, Data(#"{"events":["{not json"],"cursor":null}"#.utf8))
        }
        defer { StubURLProtocol.reset() }
        await #expect(throws: BackendError.self) {
            _ = try await Self.backend().pullEvents(after: nil)
        }
    }

    // MARK: Recognition

    @Test("An empty message is refused before it costs a call")
    func refusesEmpty() async throws {
        let sent = Captured()
        StubURLProtocol.install { request in
            sent.append(request)
            return (201, Data())
        }
        defer { StubURLProtocol.reset() }
        await #expect(throws: BackendError.self) {
            try await Self.backend().recognize(said: "   ")
        }
        #expect(sent.requests.isEmpty)
    }

    // MARK: Corrections

    @Test("A meal correction names the stored photo when there is one, and the current list either way")
    func refinesMeal() async throws {
        let sent = Captured()
        StubURLProtocol.install { request in
            sent.append(request)
            return (201, Data(#"{"revision":{"add":[],"revise":[],"dish_counts":[],"dish_names":[],"remove":[],"notes":null},"promptVersion":"x","model":"m","providerRequestId":null}"#.utf8))
        }
        defer { StubURLProtocol.reset() }
        let dishes = [MealDish(name: "beer", count: 3, items: [MealItem(label: "lager", grams: 1500, per100g: .zero)])]

        let revision = try await Self.backend().refine(meal: dishes, note: "one can, not three")
        #expect(revision.isEmpty)
        #expect(sent.requests[0].url?.path == "/v1/refinements")
        let body = try JSONSerialization.jsonObject(with: Data(sent.bodies[0].utf8)) as? [String: Any]
        #expect((body?["current"] as? [[String: Any]])?.first?["label"] as? String == "lager")
        #expect(((body?["dishes"] as? [[String: Any]])?.first?["item_indices"] as? [Int]) == [1])
        #expect(body?["note"] as? String == "one can, not three")

        _ = try await Self.backend().refine(meal: dishes, note: "x", photoHash: "ABCDEF")
        #expect(sent.requests[1].url?.path == "/v1/recognitions/abcdef/refine")
    }

    @Test("Sign-in omits a stale session, so an expired credential cannot block recovery")
    func signInOmitsSession() async throws {
        let sent = Captured()
        StubURLProtocol.install { request in
            sent.append(request)
            let answer = #"{"accountId":"acc","sessionToken":"fresh","expiresAt":1,"accountCreated":false}"#
            return (200, Data(answer.utf8))
        }
        defer { StubURLProtocol.reset() }

        let result = try await Self.backend(token: "stale").signIn(provider: .apple, identityToken: "jwt", nonce: "raw")
        #expect(result.sessionToken == "fresh")
        #expect(sent.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        let body = try JSONSerialization.jsonObject(with: Data(sent.bodies[0].utf8)) as? [String: Any]
        #expect(body?["nonce"] as? String == "raw")
    }

    @Test("A non-2xx answer surfaces the Worker's own message")
    func surfacesError() async throws {
        StubURLProtocol.install { _ in (401, Data(#"{"error":"Session expired."}"#.utf8)) }
        defer { StubURLProtocol.reset() }
        await #expect(throws: BackendError.http(status: 401, message: "Session expired.")) {
            try await Self.backend().signOut()
        }
    }
}

// MARK: - Stub transport

/// What the stub saw, in order. A class so the `@Sendable` handler can append.
private final class Captured: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []
    private var _bodies: [String] = []

    var requests: [URLRequest] { lock.withLock { _requests } }
    var bodies: [String] { lock.withLock { _bodies } }

    func append(_ request: URLRequest) {
        lock.withLock {
            _requests.append(request)
            _bodies.append(String(decoding: request.bodyBytes, as: UTF8.self))
        }
    }
}

extension URLRequest {
    /// `URLSession` moves `httpBody` into a stream before a `URLProtocol` sees
    /// the request; read whichever is there.
    fileprivate var bodyBytes: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ value: @escaping Handler) { lock.withLock { handler = value } }
    static func reset() { lock.withLock { handler = nil } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.lock.withLock { Self.handler }
        do {
            guard let handler, let url = request.url else { throw URLError(.badURL) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
