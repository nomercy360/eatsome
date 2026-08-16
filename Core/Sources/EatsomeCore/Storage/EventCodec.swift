import Foundation

/// The one place a log line becomes an event and an event becomes a log line.
///
/// It owns the single `JSONEncoder`/`JSONDecoder` pair, which is why `RawJSON`
/// takes an encoder as a parameter rather than defaulting one: two encoder
/// configurations in a codebase that writes an append-only file is two spellings
/// of the same record, and they drift.
///
/// Reading is two-pass by necessity. The first pass probes the envelope for
/// `payload.kind` while keeping the line whole; the second decodes the body the
/// kind selected. A kind this build does not know skips the second pass and the
/// line is retained verbatim as `.unrecognized`.
public struct EventCodec: Sendable {
    public init() {}

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Reading

    public enum ReadError: Error, Sendable {
        /// The line is not JSON, or is JSON that has no usable envelope. This
        /// is the only remaining meaning of "unreadable": genuinely corrupt,
        /// not merely newer.
        case malformedEnvelope(line: String, underlying: String)
        /// The envelope parsed and the kind was known, but its body did not.
        /// A newer build wrote a field this one cannot make sense of *inside* a
        /// kind it does know, which is a real incompatibility rather than a
        /// forward-compatible addition.
        case malformedBody(kind: String, underlying: String)
    }

    public func event(from line: RawJSON) throws -> LoggedEvent {
        let envelope: EventEnvelope
        do {
            envelope = try line.probe(EventEnvelope.self, using: decoder)
        } catch {
            throw ReadError.malformedEnvelope(
                line: line.text,
                underlying: String(describing: error)
            )
        }

        guard let kind = EventPayload.Kind(rawValue: envelope.payload.kind) else {
            return LoggedEvent(
                id: envelope.id,
                occurredAt: envelope.occurredAt,
                recordedAt: envelope.recordedAt,
                payload: .unrecognized(kind: envelope.payload.kind, line: line)
            )
        }

        do {
            let payload: EventPayload = switch kind {
            case .mealLogged: .mealLogged(try body(MealEntry.self, from: line))
            case .mealRevised: .mealRevised(try body(MealEntry.self, from: line))
            case .mealDeleted: .mealDeleted(mealID: try body(MealRef.self, from: line).mealID)
            case .messageSent: .messageSent(try body(LogMessage.self, from: line))
            case .messageDeleted:
                .messageDeleted(messageID: try body(MessageRef.self, from: line).messageID)
            }
            return LoggedEvent(
                id: envelope.id,
                occurredAt: envelope.occurredAt,
                recordedAt: envelope.recordedAt,
                payload: payload
            )
        } catch {
            throw ReadError.malformedBody(
                kind: envelope.payload.kind,
                underlying: String(describing: error)
            )
        }
    }

    private func body<Body: Decodable>(_ type: Body.Type, from line: RawJSON) throws -> Body {
        try line.probe(DecodableEvent<Body>.self, using: decoder).payload.data
    }

    // MARK: Writing

    /// One line, ready to append.
    ///
    /// A retained unknown event returns its original bytes. Everything else is
    /// encoded. `RawJSON` is not `Encodable`, so a future caller that skips
    /// this switch does not compile rather than silently rewriting somebody's
    /// record.
    public func line(for event: LoggedEvent) throws -> RawJSON {
        switch event.payload {
        case .unrecognized(_, let line):
            return line
        case .mealLogged(let meal):
            return try encoded(event, EventPayload.Kind.mealLogged, meal)
        case .mealRevised(let meal):
            return try encoded(event, EventPayload.Kind.mealRevised, meal)
        case .mealDeleted(let id):
            return try encoded(event, EventPayload.Kind.mealDeleted, MealRef(mealID: id))
        case .messageSent(let message):
            return try encoded(event, EventPayload.Kind.messageSent, message)
        case .messageDeleted(let id):
            return try encoded(event, EventPayload.Kind.messageDeleted, MessageRef(messageID: id))
        }
    }

    private func encoded<Body: Encodable>(
        _ event: LoggedEvent,
        _ kind: EventPayload.Kind,
        _ data: Body
    ) throws -> RawJSON {
        try RawJSON(
            encoding: EncodableEvent(event, kind: kind.rawValue, data: data),
            using: encoder
        )
    }

    /// The upload body for a batch of events.
    ///
    /// Spliced rather than encoded, because a batch containing a retained
    /// unknown line cannot go through `JSONEncoder` — `RawJSON` is bytes, not
    /// a value. The server stores payload bodies opaquely, so a kind it does
    /// not know is still a kind it can keep.
    public func batch(deviceID: String, events: [LoggedEvent]) throws -> RawJSON {
        let lines = try events.map(line(for:))
        return RawJSON.object([
            "deviceId": try RawJSON(encoding: deviceID, using: encoder),
            "events": RawJSON.array(lines)
        ])
    }
}
