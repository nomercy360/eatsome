import Foundation
import Testing
@testable import ShamanCore

@Suite("Backend account session", .serialized)
struct BackendSessionTests {
    @Test("Account history follows every event cursor")
    func pullsEveryEventPage() async throws {
        let first = (0..<500).map { index in
            LoggedEvent(
                id: UUIDv7.generate(at: 1_700_000_000_000 + EpochMillis(index)),
                occurredAt: EpochMillis(index),
                recordedAt: EpochMillis(index),
                payload: .messageDeleted(messageID: UUIDv7.generate(at: 1_600_000_000_000 + EpochMillis(index)))
            )
        }
        let last = LoggedEvent(
            id: UUIDv7.generate(at: 1_700_000_001_000),
            occurredAt: 500,
            recordedAt: 500,
            payload: .messageDeleted(messageID: UUIDv7.generate(at: 1_600_000_001_000))
        )
        var requests: [URLRequest] = []

        StubURLProtocol.install { request in
            requests.append(request)
            guard let url = request.url else { throw URLError(.badURL) }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let cursor = query?.queryItems?.first { $0.name == "cursor" }?.value
            let page = cursor == nil
                ? RemotePage(events: first.map(RemoteEvent.init), nextCursor: "page-1")
                : RemotePage(events: [RemoteEvent(last)], nextCursor: "page-2")
            return (200, try JSONEncoder().encode(page))
        }
        defer { StubURLProtocol.reset() }

        let events = try await backend().events()

        #expect(events.count == 501)
        #expect(events.last?.payload == last.payload)
        #expect(events.last?.sourceDeviceId == "another-phone")
        #expect(requests.count == 2)
        #expect(requests[0].value(forHTTPHeaderField: "X-Session-Token") == "account-session")
        let secondQuery = URLComponents(url: try #require(requests[1].url), resolvingAgainstBaseURL: false)
        #expect(secondQuery?.queryItems?.contains { $0.name == "cursor" && $0.value == "page-1" } == true)
    }

    @Test("Apple sign-in can recover from a stale local session")
    func signInOmitsExistingSession() async throws {
        var request: URLRequest?
        StubURLProtocol.install { value in
            request = value
            return (
                201,
                Data(
                    #"{"accountId":"acct:one","sessionToken":"fresh","expiresAt":1900000000000,"accountCreated":false,"merge":{"partition":"device:phone","adopted":true,"conflict":null}}"#.utf8
                )
            )
        }
        defer { StubURLProtocol.reset() }

        let result = try await backend().signIn(
            provider: .apple,
            identityToken: "apple-token",
            nonce: "nonce"
        )

        #expect(result.sessionToken == "fresh")
        #expect(request?.value(forHTTPHeaderField: "X-Session-Token") == nil)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer build-token")
    }

    @Test("Re-upload strips read-only source-device provenance")
    func syncStripsSourceDevice() async throws {
        var body: [String: Any]?
        StubURLProtocol.install { request in
            let requestBody = try bodyData(for: request)
            body = try JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
            return (200, Data(#"{"accepted":1,"inserted":0,"replayed":1}"#.utf8))
        }
        defer { StubURLProtocol.reset() }

        let remote = LoggedEvent(
            occurredAt: 1,
            recordedAt: 2,
            payload: .messageDeleted(messageID: UUIDv7.generate(at: 1_600_000_002_000)),
            sourceDeviceId: "another-phone"
        )
        try await backend().syncEvents([remote])

        let events = try #require(body?["events"] as? [[String: Any]])
        #expect(events.count == 1)
        #expect(events[0]["sourceDeviceId"] == nil)
    }

    @Test("A fresh install can download a private meal photo")
    func downloadsMealPhoto() async throws {
        let expected = Data("private-photo".utf8)
        let hash = String(repeating: "A", count: 64)
        var request: URLRequest?
        StubURLProtocol.install { value in
            request = value
            return (200, expected)
        }
        defer { StubURLProtocol.reset() }

        let received = try await backend().mealPhoto(hash: hash)

        #expect(received == expected)
        #expect(request?.url?.path == "/api/v1/media/\(hash.lowercased())")
        #expect(request?.value(forHTTPHeaderField: "X-Session-Token") == "account-session")
    }

    private func backend() -> BackendSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return BackendSession(
            configuration: .init(
                baseURL: URL(string: "https://example.test/api/v1")!,
                token: "build-token",
                deviceID: "phone-device-id",
                sessionToken: "account-session"
            ),
            session: URLSession(configuration: configuration)
        )
    }
}

private func bodyData(for request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { throw URLError(.badURL) }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
        if count == 0 { break }
        result.append(buffer, count: count)
    }
    return result
}

private struct RemotePage: Encodable {
    let events: [RemoteEvent]
    let nextCursor: String
}

private struct RemoteEvent: Encodable {
    let event: LoggedEvent

    init(_ event: LoggedEvent) { self.event = event }

    private enum CodingKeys: String, CodingKey {
        case id, occurredAt, recordedAt, payload, sourceDeviceId
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(event.id, forKey: .id)
        try container.encode(event.occurredAt, forKey: .occurredAt)
        try container.encode(event.recordedAt, forKey: .recordedAt)
        try container.encode(event.payload, forKey: .payload)
        try container.encode("another-phone", forKey: .sourceDeviceId)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = (URLRequest) throws -> (status: Int, data: Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?

    static func install(_ value: @escaping Handler) {
        lock.lock()
        handler = value
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let handler = Self.handler
        Self.lock.unlock()
        do {
            guard let handler, let url = request.url else { throw URLError(.badURL) }
            let output = try handler(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: output.status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: output.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
