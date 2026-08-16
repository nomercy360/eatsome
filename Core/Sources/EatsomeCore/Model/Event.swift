import Foundation

/// The app stores an append-only log of events, never mutable rows.
///
/// Two reasons. First, a correction is itself information — "the model said
/// white meat, I said fish" is the data that tells you whether the recognition
/// prompt needs work, and an UPDATE destroys it. Second, an append-only log can
/// be uploaded idempotently before its ids define the server's desired mirror;
/// mutable rows would require a field-by-field conflict policy.
public struct LoggedEvent: Sendable, Hashable, Identifiable {
    public let id: UUID
    /// When the thing happened in the world.
    public let occurredAt: EpochMillis
    /// When we wrote it down. Differs from `occurredAt` when you log lunch at
    /// 9pm.
    public let recordedAt: EpochMillis
    public let payload: EventPayload

    public init(
        id: UUID = UUIDv7.generate(),
        occurredAt: EpochMillis,
        recordedAt: EpochMillis = Date().epochMillis,
        payload: EventPayload
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.payload = payload
    }
}

public enum EventPayload: Sendable, Hashable {
    case mealLogged(MealEntry)
    /// Supersedes an earlier `mealLogged` with the same meal id.
    case mealRevised(MealEntry)
    case mealDeleted(mealID: UUID)

    /// Something you said, written down the moment you said it — before anyone
    /// knows what it means. This is what makes logging work offline and makes a
    /// failed reading retryable rather than retypeable.
    case messageSent(LogMessage)
    case messageDeleted(messageID: UUID)

    /// An event written by a build newer than this one, kept whole.
    ///
    /// The mirror is a union of immutable events across every device on the
    /// account, so a phone routinely holds lines another build wrote. An
    /// unknown kind is therefore a value, not a failure. It renders nothing, counts
    /// for nothing, and re-emits byte for byte. `line` is the entire original
    /// record rather than the payload's `data`, because the unit of writing is
    /// the line and `id`/`occurredAt`/`recordedAt` are read from the envelope,
    /// whose shape is fixed. If the *envelope* will not parse, that is a
    /// genuinely corrupt line and is treated as one.
    ///
    /// This does not reintroduce the failure that `schemaVersion` exists to
    /// prevent. That rule is about a *meal* of an unknown version decoding to a
    /// plausible number; this decodes to something explicitly opaque that no
    /// screen can display and no total can include.
    case unrecognized(kind: String, line: RawJSON)
}

// MARK: - Wire format

extension EventPayload {
    /// The `kind` string for every case this build understands. An unknown
    /// value here is what produces `.unrecognized`.
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case mealLogged = "meal_logged"
        case mealRevised = "meal_revised"
        case mealDeleted = "meal_deleted"
        case messageSent = "message_sent"
        case messageDeleted = "message_deleted"
    }

    /// The wire `kind`, including for a retained unknown one.
    public var kind: String {
        switch self {
        case .mealLogged: Kind.mealLogged.rawValue
        case .mealRevised: Kind.mealRevised.rawValue
        case .mealDeleted: Kind.mealDeleted.rawValue
        case .messageSent: Kind.messageSent.rawValue
        case .messageDeleted: Kind.messageDeleted.rawValue
        case .unrecognized(let kind, _): kind
        }
    }

    /// True for an event this build cannot interpret. Everything that folds,
    /// counts, or displays checks this rather than switching and forgetting a
    /// case.
    public var isUnrecognized: Bool {
        if case .unrecognized = self { return true }
        return false
    }
}

/// The envelope, minus the payload body — what a reader learns before it knows
/// whether it understands the rest. Decoded from a retained line by
/// `RawJSON.probe`.
struct EventEnvelope: Decodable {
    let id: UUID
    let occurredAt: EpochMillis
    let recordedAt: EpochMillis
    let payload: PayloadKind

    struct PayloadKind: Decodable {
        let kind: String
    }
}

/// The full envelope for a kind this build understands. Two-pass: the probe
/// above reads `kind`, then this decodes the body it selected.
struct DecodableEvent<Body: Decodable>: Decodable {
    let id: UUID
    let occurredAt: EpochMillis
    let recordedAt: EpochMillis
    let payload: Payload

    struct Payload: Decodable {
        let data: Body
    }
}

/// The encodable form of an event this build wrote. `unrecognized` never
/// reaches here — it is re-emitted from its retained bytes instead, and
/// `RawJSON` throws if anyone tries to put it through an encoder.
struct EncodableEvent<Body: Encodable>: Encodable {
    let id: UUID
    let occurredAt: EpochMillis
    let recordedAt: EpochMillis
    let payload: Payload

    struct Payload: Encodable {
        let kind: String
        let data: Body
    }

    init(_ event: LoggedEvent, kind: String, data: Body) {
        self.id = event.id
        self.occurredAt = event.occurredAt
        self.recordedAt = event.recordedAt
        self.payload = Payload(kind: kind, data: data)
    }
}

/// A payload body that is only an id, for the three delete kinds.
struct MealRef: Codable { let mealID: UUID }
struct MessageRef: Codable { let messageID: UUID }
