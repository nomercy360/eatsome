import Foundation

/// One thing you said to the app: words, a photograph, or both.
///
/// Logging is a thread now, and a message is the unit of it. The important
/// property is that a message is recorded the instant it is sent, before anyone
/// knows what it means — it works offline, it survives the app being killed
/// mid-read, and a recognition that fails is a message that can be re-sent
/// rather than a meal that has to be re-typed.
///
/// That is also why the message is stored *beside* the meal rather than being
/// replaced by it. The thread shows both: the blue bubble is what you said, the
/// card underneath is what the app made of it. Keeping them apart means a
/// correction never edits your own words, and six months later "I typed 'big
/// bowl' and it logged a small one" is still answerable from the log.
public struct LogMessage: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// When it was sent, which is not when it was read and not necessarily when
    /// the food was eaten — "half a kebab at 2 am" can arrive at noon.
    public var sentAt: EpochMillis
    /// What was typed or dictated. Nil for a bare photograph with no caption.
    ///
    /// Voice lands here as text, deliberately: what the transcriber heard is
    /// what gets parsed, so a wrong word is visible and fixable before it is
    /// sent rather than mysterious afterwards.
    public var said: String?
    /// SHA-256 of the attached photo's bytes, when there was one. The same hash
    /// `PhotoStore` files the image under and recognition keys its cache on.
    public var photoHash: String?

    public init(
        id: UUID = UUIDv7.generate(),
        sentAt: EpochMillis = Date().epochMillis,
        said: String? = nil,
        photoHash: String? = nil
    ) {
        self.id = id
        self.sentAt = sentAt
        self.said = said
        self.photoHash = photoHash
    }

    /// A message with neither words nor a picture is not a message. Guarded here
    /// so nothing downstream has to decide what an empty one means — and so a
    /// stray send can never buy a model call.
    public var isEmpty: Bool {
        (said?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && photoHash == nil
    }

    public var trimmedText: String? {
        let text = said?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }
}

/// Where a message has got to.
///
/// Deliberately *not* stored. Sent and logged are both facts already in the
/// event log — the message is there, and the meal either references it or does
/// not — while reading and failed are properties of an attempt in flight on this
/// device right now. Persisting "reading" would mean a crash mid-recognition
/// left a message stuck in a state nothing could clear, which is exactly the
/// kind of bug an append-only log is supposed to make impossible.
public enum LogMessageState: Sendable, Hashable {
    /// Written down, waiting its turn. Works offline; goes when it can.
    case sent
    /// A model is reading it. The composer does not lock — the next message can
    /// be sent while this one is still being read, and they may finish in any
    /// order.
    case reading
    /// It became a meal. `mealID` is the card the thread draws under the bubble.
    case logged(mealID: UUID)
    /// The read did not complete. The message survives intact, so retrying
    /// re-sends it and never asks anyone to type it again.
    case failed(reason: String)
}
