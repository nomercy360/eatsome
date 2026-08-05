import Foundation

/// A dish you cook yourself, described once and logged again.
///
/// This exists because photographs have a ceiling that no model clears: home
/// cooking hides its ingredients. French toast is two eggs, milk, sugar, and the
/// butter it was fried in, and none of that is in the frame — the camera sees
/// crust, banana, and shine. A better vision model does not fix that; the
/// information is not in the image.
///
/// Restaurant food is different every time and worth photographing. Home food
/// repeats, so it is worth typing once. Correct the recognition once, save it,
/// and the invisible half comes back with it.
public struct Recipe: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    public var items: [MealItem]
    /// The line you would have written next to the photo: what it cannot show.
    /// Carried into recognition when the recipe is used with a picture.
    public var note: String?
    public var updatedAt: EpochMillis

    public init(
        id: UUID = UUIDv7.generate(),
        name: String,
        items: [MealItem],
        note: String? = nil,
        updatedAt: EpochMillis = Date().epochMillis
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.note = note
        self.updatedAt = updatedAt
    }

    /// A fresh meal from this recipe. Item ids are regenerated: two dinners of
    /// the same dish are two events, and sharing item ids between them would
    /// make the log lie about which one you corrected.
    public func newMeal(eatenAt: EpochMillis, share: MealShare = .whole) -> MealEntry {
        MealEntry(
            eatenAt: eatenAt,
            items: items.map {
                MealItem(group: $0.group, portion: $0.portion, label: $0.label)
            },
            source: .recipe,
            note: note,
            share: share
        )
    }

    /// The obvious name for a dish assembled from recognition, so saving one is
    /// a tap rather than a typing exercise.
    public static func suggestedName(for items: [MealItem]) -> String {
        let labels = items.compactMap(\.label).filter { !$0.isEmpty }
        if !labels.isEmpty { return labels.prefix(2).joined(separator: ", ") }
        return items.prefix(2).map(\.group.displayName).joined(separator: ", ")
    }
}
