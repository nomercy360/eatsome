import Foundation

public struct MealItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var group: FoodGroup
    public var portion: Portion
    /// Free text from the model ("grilled sardines"). Never scored — it exists
    /// so the correction sheet can show you what the model thought it saw.
    public var label: String?

    public init(id: UUID = UUIDv7.generate(), group: FoodGroup, portion: Portion, label: String? = nil) {
        self.id = id
        self.group = group
        self.portion = portion
        self.label = label
    }
}

public enum MealSource: String, Codable, Sendable {
    case photo
    case manual
}

public struct MealEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var eatenAt: EpochMillis
    public var items: [MealItem]
    public var source: MealSource
    /// SHA-256 of the original image bytes. Doubles as the recognition cache key,
    /// so re-submitting the same photo never costs a second API call.
    public var photoHash: String?
    public var modelConfidence: Double?
    /// True once you have touched the result. Uncorrected model output and
    /// human-confirmed output are not the same evidence and should not be
    /// silently mixed when you later look at why a week scored badly.
    public var wasCorrected: Bool

    public init(
        id: UUID = UUIDv7.generate(),
        eatenAt: EpochMillis,
        items: [MealItem],
        source: MealSource,
        photoHash: String? = nil,
        modelConfidence: Double? = nil,
        wasCorrected: Bool = false
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.items = items
        self.source = source
        self.photoHash = photoHash
        self.modelConfidence = modelConfidence
        self.wasCorrected = wasCorrected
    }

    public func servings(of group: FoodGroup) -> Double {
        items.filter { $0.group == group }.reduce(0) { $0 + $1.portion.servings }
    }
}

/// One-off answers that a photo cannot establish. MEDAS item 1 ("is olive oil
/// your main culinary fat") and item 13 ("do you prefer white meat to red") are
/// habits, not events.
public struct DietHabits: Codable, Sendable, Hashable {
    public var oliveOilIsMainCulinaryFat: Bool
    public var prefersWhiteMeatOverRed: Bool

    public init(oliveOilIsMainCulinaryFat: Bool = true, prefersWhiteMeatOverRed: Bool = true) {
        self.oliveOilIsMainCulinaryFat = oliveOilIsMainCulinaryFat
        self.prefersWhiteMeatOverRed = prefersWhiteMeatOverRed
    }
}
