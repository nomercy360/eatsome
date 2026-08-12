import Foundation

/// Where one nutrient figure came from.
///
/// Composition used to be looked up in a table shipped with the app, and the
/// only interesting question about a figure was whether the lookup had found
/// anything. From v21 the figure arrives with the food, so the interesting
/// question is who said it — and the four answers are not equally strong.
///
/// This is the whole of what replaced `NutrientResolution`. There is no `table`
/// case because there is no table: the v21 migration re-prices every meal in the
/// log through the same path a new meal takes, so no stored figure anywhere was
/// produced by a lookup.
public enum NutrientSource: String, Codable, Sendable, Hashable, CaseIterable {
    /// Transcribed from a panel visible in the photograph — packaging, a menu, a
    /// price card. The strongest thing there is: a printed fact about the exact
    /// item in front of the camera.
    case panel
    /// Fetched from the manufacturer's or restaurant's own published figures.
    /// A fact too, but about a product rather than about this plate, so it
    /// carries `SourceRef` to say which product, which market, and whether the
    /// serving had to be scaled to match.
    case published
    /// The model's own composition figure for the food it named.
    case model
    /// Typed or corrected by hand. Outranks everything, because the person was
    /// there and nothing else was.
    case user

    /// An unknown value is a source written by a build newer than this one. A
    /// meal that will not decode vanishes from the projection, and a vague
    /// provenance label is a far smaller loss than a missing meal.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NutrientSource(rawValue: raw) ?? .model
    }
}

/// Which source supplied each of the five figures.
///
/// Per figure rather than per item, because a panel is routinely partial: a
/// carton printing protein and energy but no sodium contributes two read figures
/// and three from the model, and flattening that to one label per item would
/// throw away the only part that was actually printed.
public struct NutrientProvenance: Codable, Sendable, Hashable {
    public var protein: NutrientSource
    public var fat: NutrientSource
    public var carbohydrate: NutrientSource
    public var kcal: NutrientSource
    public var sodium: NutrientSource

    public init(
        protein: NutrientSource = .model,
        fat: NutrientSource = .model,
        carbohydrate: NutrientSource = .model,
        kcal: NutrientSource = .model,
        sodium: NutrientSource = .model
    ) {
        self.protein = protein
        self.fat = fat
        self.carbohydrate = carbohydrate
        self.kcal = kcal
        self.sodium = sodium
    }

    /// All five from one source, which is the ordinary case.
    public static func all(_ source: NutrientSource) -> NutrientProvenance {
        NutrientProvenance(
            protein: source, fat: source, carbohydrate: source, kcal: source, sodium: source
        )
    }

    public static let model = NutrientProvenance.all(.model)

    public var sources: [NutrientSource] { [protein, fat, carbohydrate, kcal, sodium] }

    /// Whether every figure was read rather than estimated. What a screen may
    /// use to drop a qualifier it would otherwise have to show.
    public var isEntirelyRead: Bool {
        sources.allSatisfy { $0 == .panel || $0 == .published || $0 == .user }
    }
}

/// Which published figures a `published` nutrient came from.
///
/// Kept because the scaling is the part that can be wrong. A Footlong priced by
/// doubling a Regular is a different claim from a figure printed for the item
/// ordered, and once the two are flattened into one number the difference cannot
/// be recovered. `scaleBasis` is the field that makes a wrong figure arguable.
public struct SourceRef: Codable, Sendable, Hashable {
    public var url: String
    public var fetchedAt: EpochMillis
    /// ISO country of the market the figures were published for. The same
    /// product is a different food in a different market, and a Big Mac scored
    /// against the wrong country is wrong by more than rounding.
    public var market: String?
    /// What the published serving was multiplied by to reach this portion.
    public var scaleFactor: Double?
    /// `same_serving`, `official_relation`, or `geometric_inference` — the last
    /// meaning the relation was inferred from size rather than stated.
    public var scaleBasis: String?
    /// The source's own name for what was priced, so a wrong number can be
    /// traced without re-fetching.
    public var productName: String?

    public init(
        url: String,
        fetchedAt: EpochMillis,
        market: String? = nil,
        scaleFactor: Double? = nil,
        scaleBasis: String? = nil,
        productName: String? = nil
    ) {
        self.url = url
        self.fetchedAt = fetchedAt
        self.market = market
        self.scaleFactor = scaleFactor
        self.scaleBasis = scaleBasis
        self.productName = productName
    }
}
