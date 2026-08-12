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
    /// What it is made of, as dishes — the same shape a recognised meal stores,
    /// so logging one is a copy rather than a conversion.
    public var dishes: [MealDish]
    /// The line you would have written next to the photo: what it cannot show.
    /// Carried into recognition when the recipe is used with a picture.
    public var note: String?
    public var updatedAt: EpochMillis

    public init(
        id: UUID = UUIDv7.generate(),
        name: String,
        dishes: [MealDish],
        note: String? = nil,
        updatedAt: EpochMillis = Date().epochMillis
    ) {
        self.id = id
        self.name = name
        self.dishes = dishes
        self.note = note
        self.updatedAt = updatedAt
    }

    public var items: [MealItem] { dishes.flatMap(\.items) }

    /// A fresh meal from this recipe. Ids are regenerated: two dinners of the
    /// same dish are two events, and sharing ids between them would make the log
    /// lie about which one you corrected.
    public func newMeal(eatenAt: EpochMillis, share: MealShare = .whole) -> MealEntry {
        MealEntry(
            eatenAt: eatenAt,
            dishes: dishes.map { dish in
                MealDish(
                    name: dish.name,
                    count: dish.count,
                    panel: dish.panel,
                    items: dish.items.map {
                        MealItem(
                            label: $0.label,
                            grams: $0.grams,
                            per100g: $0.per100g,
                            provenance: $0.provenance,
                            preparation: $0.preparation,
                            sourceRef: $0.sourceRef
                        )
                    }
                )
            },
            source: .recipe,
            note: note,
            share: share,
            recipeID: id
        )
    }

    /// The obvious name for a meal assembled from recognition, so saving one is
    /// a tap rather than a typing exercise.
    public static func suggestedName(for dishes: [MealDish]) -> String {
        let names = dishes.compactMap(\.name).filter { !$0.isEmpty }
        if !names.isEmpty { return names.prefix(2).joined(separator: ", ") }
        let labels = dishes.flatMap(\.items).map(\.label).filter { !$0.isEmpty }
        return labels.prefix(2).joined(separator: ", ")
    }
}
