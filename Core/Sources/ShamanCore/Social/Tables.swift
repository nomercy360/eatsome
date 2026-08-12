import Foundation

/// A table: your log, with friends in it.
///
/// The Swift half of the contract in `Backend/src/contracts.ts`. Two properties
/// of that contract are load-bearing on this side too, and both are the kind a
/// client can quietly break:
///
/// - **No account id ever crosses a table.** It is the server-side key to a
///   person's private partition; putting one in a row a tablemate can read
///   would expose an identifier that has no social purpose. Members are named
///   by a per-table `memberId`
///   and the name they typed, and there is deliberately nowhere in these types
///   to put an account id.
/// - **A post is a copy, not a reference.** What was shared is what these types
///   carry; nothing here resolves back into a `MealEntry`. So a meal corrected
///   tomorrow does not rewrite the card a friend replied to today, and no
///   future private field on `MealEntry` can leak through a redactor somebody
///   forgot to update.
public struct TableMember: Codable, Sendable, Hashable, Identifiable {
    public let memberId: String
    public let displayName: String
    public let role: String
    public let isMe: Bool

    public var id: String { memberId }

    public var isCreator: Bool { role == "creator" }

    /// The single letter a square avatar shows.
    public var initial: String {
        String(displayName.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

public struct PostReactions: Codable, Sendable, Hashable {
    public let kind: String
    public let count: Int
    /// Whether the caller is one of the count. Sent by the server rather than
    /// tracked here, so a second device shows the same state.
    public let mine: Bool

    public init(kind: String, count: Int, mine: Bool) {
        self.kind = kind
        self.count = count
        self.mine = mine
    }
}

public struct TablePost: Codable, Sendable, Hashable, Identifiable {
    public init(
        id: String, seq: Int, kind: String, authorMemberId: String, authorName: String,
        mine: Bool, createdAt: EpochMillis, mealId: String?, dishName: String?,
        caption: String?, ingredients: [PostIngredient]?, hasPhoto: Bool,
        text: String?, replyToPostId: String?, reactions: [PostReactions]
    ) {
        self.id = id; self.seq = seq; self.kind = kind
        self.authorMemberId = authorMemberId; self.authorName = authorName
        self.mine = mine; self.createdAt = createdAt; self.mealId = mealId
        self.dishName = dishName; self.caption = caption; self.ingredients = ingredients
        self.hasPhoto = hasPhoto; self.text = text; self.replyToPostId = replyToPostId
        self.reactions = reactions
    }

    public let id: String
    /// Server-assigned, per-table, monotonic — the feed's one total order. No
    /// device clock is trusted to sort somebody else's dinner.
    public let seq: Int
    public let kind: String
    public let authorMemberId: String
    public let authorName: String
    public let mine: Bool
    public let createdAt: EpochMillis

    // share
    /// Provenance only. Which meal this came from, never resolved on read.
    public let mealId: String?
    public let dishName: String?
    public let caption: String?
    public let ingredients: [PostIngredient]?
    public let hasPhoto: Bool

    // message
    public let text: String?
    public let replyToPostId: String?

    public let reactions: [PostReactions]

    public var isShare: Bool { kind == "share" }
    public var isReply: Bool { replyToPostId != nil }

    public func reaction(_ kind: TableReaction) -> PostReactions? {
        reactions.first { $0.kind == kind.rawValue }
    }

    /// The same post with one reaction toggled, for drawing a tap before the
    /// server has agreed to it.
    ///
    /// In Core rather than in the view because it is arithmetic on the contract
    /// — a count moves by one and `mine` follows — and a view that owns that
    /// arithmetic is a view that can drift from what the server would have
    /// returned.
    public func reacted(_ kind: TableReaction, on: Bool) -> TablePost {
        var updated: [PostReactions] = []
        var found = false
        for reaction in reactions {
            guard reaction.kind == kind.rawValue else { updated.append(reaction); continue }
            found = true
            guard reaction.mine != on else { updated.append(reaction); continue }
            updated.append(PostReactions(
                kind: reaction.kind,
                count: max(0, reaction.count + (on ? 1 : -1)),
                mine: on
            ))
        }
        if !found, on {
            updated.append(PostReactions(kind: kind.rawValue, count: 1, mine: true))
        }
        return TablePost(
            id: id, seq: seq, kind: self.kind, authorMemberId: authorMemberId,
            authorName: authorName, mine: mine, createdAt: createdAt,
            mealId: mealId, dishName: dishName, caption: caption,
            ingredients: ingredients, hasPhoto: hasPhoto,
            text: text, replyToPostId: replyToPostId, reactions: updated
        )
    }

    /// The same immutable post after its author edits the one allowed line.
    public func withCaption(_ caption: String?) -> TablePost {
        TablePost(
            id: id, seq: seq, kind: kind, authorMemberId: authorMemberId,
            authorName: authorName, mine: mine, createdAt: createdAt,
            mealId: mealId, dishName: dishName, caption: caption,
            ingredients: ingredients, hasPhoto: hasPhoto,
            text: text, replyToPostId: replyToPostId, reactions: reactions
        )
    }

    /// The mono line under a shared dish: what was in it, in chip vocabulary.
    ///
    /// Empty when the sharer left "show what's in it" off, which is the
    /// redaction working — absence is the whole of it, and a card with no
    /// ingredient line is a card whose owner said no.
    public var ingredientLine: String {
        guard let ingredients, !ingredients.isEmpty else { return "" }
        var seen: [String] = []
        for row in ingredients {
            let text = row.label.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            if !seen.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) {
                seen.append(text)
            }
        }
        return seen.prefix(4).joined(separator: ", ")
    }
}

/// One shared ingredient, and the whole of what a friend's card may say about
/// food: what it was and how much of it. No alternatives, no provenance, no
/// evidence — a friend's card answers "what's in it", never "how did they do".
///
/// Composition rides along because the reader has no table to look it up in.
/// That was true before v21 too; it simply used to be hidden by the fact that
/// both devices shipped the same one.
public struct PostIngredient: Codable, Sendable, Hashable {
    public let label: String
    public let grams: Double
    public let per100g: Nutrients

    public init(label: String, grams: Double, per100g: Nutrients) {
        self.label = label
        self.grams = grams
        self.per100g = per100g
    }

    private enum CodingKeys: String, CodingKey {
        case label, grams
        case per100g = "per_100g"
    }
}

public enum TableReaction: String, Codable, Sendable, CaseIterable {
    /// The server values stay stable so an upgraded app can react to plates
    /// written by older builds without rewriting reaction rows in place.
    case fire = "olive"
    case sushi = "heart"
}

/// What the current member allows this table to receive. Photos default on;
/// personal numbers default off. Keeping this on the membership rather than
/// the table means every person at the same table owns their own boundary.
public struct TableVisibility: Codable, Sendable, Hashable {
    public let photos: Bool
    public let nutrition: Bool
    public let bodyAndGoals: Bool

    public init(photos: Bool = true, nutrition: Bool = false, bodyAndGoals: Bool = false) {
        self.photos = photos
        self.nutrition = nutrition
        self.bodyAndGoals = bodyAndGoals
    }

    public static let privateByDefault = TableVisibility()
}

/// The small, intentionally redacted slice used by the Tables list. It carries
/// enough to draw a photo strip without making the list download whole posts.
public struct TablePlatePreview: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let authorName: String
    public let mine: Bool
    public let createdAt: EpochMillis
    public let hasPhoto: Bool
    public let reactionCount: Int
}

public struct TableSummary: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let members: [TableMember]
    public let inviteCode: String
    /// Nil against a pre-link API. The client still forms a link from the
    /// stable invite code, while a current server supplies the real deadline.
    public let inviteExpiresAt: EpochMillis?
    /// Nil against a pre-privacy API; private-by-default is the safe fallback.
    public let visibility: TableVisibility?
    /// Counted by the server against the same snapshot as the rest of the
    /// response. Never recomputed here from a page of posts — that is exactly
    /// how a badge undercounts while looking exact.
    public let unreadCount: Int
    public let latestSeq: Int
    public let myLastReadSeq: Int
    /// Distinct members who shared a meal since the caller's own start-of-day.
    /// Nil when the client did not say where its day begins, which is a
    /// different fact from zero and must not be drawn as one.
    public let cookedToday: Int?
    /// Number of plates, not distinct cooks, since the caller's local midnight.
    public let platesToday: Int?
    /// Newest first. Optional so the app remains decodable during a rolling API
    /// deployment where the old server has not started sending photo previews.
    public let recentPlates: [TablePlatePreview]?
    public let latest: LatestPost?

    public struct LatestPost: Codable, Sendable, Hashable {
        public let authorName: String
        public let text: String
        public let createdAt: EpochMillis
    }

    /// "Marta: recipe?? they look unreal" — the slim row under the day.
    public var previewLine: String? {
        latest.map { "\($0.authorName): \($0.text)" }
    }

    public var hasUnread: Bool { unreadCount > 0 }

    public var effectiveVisibility: TableVisibility { visibility ?? .privateByDefault }

    public var inviteURL: URL {
        URL(string: "eatsome://table/\(inviteCode.lowercased())")!
    }
}

public struct TablesListResponse: Codable, Sendable {
    public let tables: [TableSummary]
    /// When the server counted. Every number above is a snapshot with a lag by
    /// construction — polling on open — and a snapshot that states its time can
    /// be drawn as stale. One that does not is a number pretending to be live.
    public let asOf: EpochMillis
}

public struct TableFeedResponse: Codable, Sendable {
    public let table: TableSummary
    /// Newest first; `nextCursor` walks older.
    public let posts: [TablePost]
    public let nextCursor: Int?
    public let asOf: EpochMillis
}

// MARK: - Requests

public struct CreateTableRequest: Codable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let visibility: TableVisibility

    public init(
        name: String,
        displayName: String,
        visibility: TableVisibility = .privateByDefault,
        id: String = UUIDv7.generate().uuidString
    ) {
        self.id = id
        self.name = name
        self.displayName = displayName
        self.visibility = visibility
    }
}

public struct JoinTableRequest: Codable, Sendable {
    public let code: String
    public let displayName: String

    /// Codes are uppercase and drawn from an alphabet with no I, L, O, 0 or 1
    /// in it, so nothing a person reads aloud is ambiguous. Typing is
    /// case-insensitive because a keyboard defaults to lowercase and a code
    /// that rejects what the keyboard produced is a code nobody can enter.
    public init(code: String, displayName: String) {
        self.code = code.trimmingCharacters(in: .whitespaces).uppercased()
        self.displayName = displayName
    }
}

/// What the share sheet sends.
///
/// A share names a photograph by hash and never carries bytes: the only route
/// where image data enters storage stays the recognition path, with its size
/// limits and its consent screen. The server copies the already-stored object
/// into one the table owns.
public enum CreatePostRequest: Encodable, Sendable {
    case share(
        id: String,
        mealId: String,
        dishName: String,
        caption: String?,
        ingredients: [PostIngredient]?,
        photoHash: String?
    )
    case message(id: String, text: String, replyToPostId: String?)

    private enum CodingKeys: String, CodingKey {
        case id, kind, mealId, dishName, caption, ingredients, photoHash, text, replyToPostId
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .share(let id, let mealId, let dishName, let caption, let ingredients, let photoHash):
            try c.encode(id, forKey: .id)
            try c.encode("share", forKey: .kind)
            try c.encode(mealId, forKey: .mealId)
            try c.encode(dishName, forKey: .dishName)
            try c.encode(caption, forKey: .caption)
            try c.encode(ingredients, forKey: .ingredients)
            try c.encode(photoHash, forKey: .photoHash)
        case .message(let id, let text, let replyToPostId):
            try c.encode(id, forKey: .id)
            try c.encode("message", forKey: .kind)
            try c.encode(text, forKey: .text)
            try c.encode(replyToPostId, forKey: .replyToPostId)
        }
    }
}

// MARK: - What a meal is allowed to become

extension MealEntry {
    /// The redaction, done once, at the moment of the tap.
    ///
    /// `showsIngredients` is the switch on the share sheet and the whole of the
    /// privacy decision: off, and the post carries a name and a photograph and
    /// nothing about the food.
    public func shareable(showingIngredients: Bool) -> [PostIngredient]? {
        guard showingIngredients else { return nil }
        return items.map { PostIngredient(label: $0.label, grams: $0.grams, per100g: $0.per100g) }
    }
}
