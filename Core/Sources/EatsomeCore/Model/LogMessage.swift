import Foundation

/// What a person said, written down the moment they said it — before anyone
/// knows what it means.
///
/// This is what makes logging work offline and what makes a failed reading
/// retryable rather than retypeable. The "Couldn't read it" screen keeps the
/// photo and the words because both are already events; nothing is lost by a
/// model that could not name a dish.
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
    /// the photo store files the image under and recognition keys its cache on.
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

    public var isEmpty: Bool {
        (said?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) && photoHash == nil
    }
}
