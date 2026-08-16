import Foundation

/// Where one nutrient figure came from.
///
/// Composition arrives with the food, so the interesting question about a figure
/// is who said it — and the answers are not equally strong. There is no `table`
/// case because there is no table, and no `published` case because nothing
/// writes one: grounded recognition returns better numbers than a fetched page
/// and returns them with no citation, so a searched answer is a better estimate
/// and the app says "estimated" about it.
public enum NutrientSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// Transcribed from a panel visible in the photograph — packaging, a menu,
    /// a price card. The strongest thing there is: a printed fact about the
    /// exact item in front of the camera.
    case panel
    /// The model's own composition figure for the food it named, whether or not
    /// it reached for search to get there.
    case model
    /// Typed or corrected by hand. Outranks everything, because the person was
    /// there and nothing else was.
    case user
}

/// Which source supplied each figure.
///
/// Per figure rather than per item, because a panel is routinely partial: a
/// carton printing protein and energy but no sodium contributes two read figures
/// and the rest from the model, and flattening that to one label per item would
/// throw away the only part that was actually printed.
public struct NutrientProvenance: Codable, Sendable, Hashable {
    public var protein: NutrientSource
    public var fat: NutrientSource
    public var carbohydrate: NutrientSource
    public var kcal: NutrientSource
    public var sodium: NutrientSource
    public var alcohol: NutrientSource
    public var caffeine: NutrientSource

    public init(
        protein: NutrientSource = .model,
        fat: NutrientSource = .model,
        carbohydrate: NutrientSource = .model,
        kcal: NutrientSource = .model,
        sodium: NutrientSource = .model,
        alcohol: NutrientSource = .model,
        caffeine: NutrientSource = .model
    ) {
        self.protein = protein
        self.fat = fat
        self.carbohydrate = carbohydrate
        self.kcal = kcal
        self.sodium = sodium
        self.alcohol = alcohol
        self.caffeine = caffeine
    }

    public static let model = NutrientProvenance()
    public static let user = NutrientProvenance(
        protein: .user, fat: .user, carbohydrate: .user,
        kcal: .user, sodium: .user, alcohol: .user, caffeine: .user
    )

    /// Every distinct source in this block, so a screen can qualify a total
    /// without re-deriving the rule.
    public var sources: Set<NutrientSource> {
        [protein, fat, carbohydrate, kcal, sodium, alcohol, caffeine]
    }
}
