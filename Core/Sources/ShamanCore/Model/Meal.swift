import Foundation

/// One food on the plate: what it is, how much of it there was, and what is in
/// it per 100 g.
///
/// v21 removed the food taxonomy and the composition table together. Until v20
/// an item carried a `kind` and the app looked the nutrition up at render time,
/// which meant every event ever written had to stay interpretable by today's
/// code — the reason `FoodKind.legacy` existed, and the reason a coarse mapping
/// silently cost 78% of logged grams. Composition now arrives with the food and
/// is stored, so an item is readable with no table, no taxonomy and no config
/// file, and nothing downstream can reinterpret it later.
///
/// `label` is the identity. It is required, because it is now the only one.
public struct MealItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// What this food is, in words: "grilled beef", "subway bread". The whole
    /// identity — there is no code to fall back to.
    public var label: String
    /// How it was cooked, when the input said. Kept structured for exactly one
    /// reason: it is what lets the correction sheet ask "grilled or fried?" with
    /// chips instead of free text. It feeds no calculation — the composition
    /// figures below already price the food as prepared.
    public var preparation: [PreparationMethod]
    /// The edible weight present, across every serving. Absolute: nothing
    /// multiplies it afterwards.
    public var grams: Double
    /// Composition per 100 g of this food.
    ///
    /// Per 100 g rather than per portion so that changing the weight — the dish
    /// count stepper, a correction, `share` — is multiplication rather than a
    /// stale number or a second round trip. It also keeps the composition claim
    /// separable from the weight claim, which matters because they fail
    /// differently and weight is where the error actually lives.
    public var per100g: Nutrients
    /// Who supplied each of the five figures.
    public var provenance: NutrientProvenance
    /// Set when any figure came from published brand figures.
    public var sourceRef: SourceRef?
    /// What else this could have been, each priced, so answering "honey or
    /// syrup?" is a local swap rather than another call. Empty means the model
    /// was asked and had no rival in mind.
    public var alternatives: [FoodAlternative]
    /// The chain or manufacturer whose menu item this row *is*, and nil for
    /// everything cooked, served loose, or added on top of one.
    ///
    /// It decides which correction a screen may offer. Weight is the control
    /// for a bowl of rice and a meaningless one for a Big Mac: nobody ate 217 g
    /// of Big Mac, they ate one, so a branded row is corrected by naming a
    /// different item, size or count.
    public var brand: String?
    /// The sizes that chain sells this item in, each priced in full. Empty for
    /// an item that comes one way, and for everything with no brand.
    public var sizes: [FoodSize]

    public init(
        id: UUID = UUIDv7.generate(),
        label: String,
        grams: Double,
        per100g: Nutrients,
        provenance: NutrientProvenance = .model,
        preparation: [PreparationMethod] = [],
        sourceRef: SourceRef? = nil,
        alternatives: [FoodAlternative] = [],
        brand: String? = nil,
        sizes: [FoodSize] = []
    ) {
        self.id = id
        self.label = label
        self.grams = grams
        self.per100g = per100g
        self.provenance = provenance
        self.preparation = preparation
        self.sourceRef = sourceRef
        self.alternatives = alternatives
        self.brand = brand
        self.sizes = sizes
    }

    /// Whether this row is something somebody's menu lists, which is the
    /// question a correction screen has to answer before it decides what to
    /// offer: chips and a stepper, or a weight.
    public var isMenuItem: Bool { !(brand?.isEmpty ?? true) }

    /// What this item contributes. Arithmetic on two stored values — not a
    /// lookup into anything that can change underneath it.
    public var nutrients: Nutrients { per100g.forGrams(grams) }

    /// `per_100g` on the wire and on disk, matching the recognition contract and
    /// `Backend/src/contracts.ts`. One spelling everywhere: the alternative is a
    /// type whose stored shape differs from the shape it arrived in, which is a
    /// mismatch nothing would catch until a round trip lost a figure.
    private enum CodingKeys: String, CodingKey {
        case id, label, grams, provenance, preparation, sourceRef, alternatives, brand, sizes
        case per100g = "per_100g"
    }

    /// `sizes` and `brand` arrived after meals were already being stored, so
    /// both decode absent. Everything else stays required — a missing weight or
    /// composition is the loud failure v21 exists to keep loud.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        grams = try container.decode(Double.self, forKey: .grams)
        per100g = try container.decode(Nutrients.self, forKey: .per100g)
        provenance = try container.decodeIfPresent(NutrientProvenance.self, forKey: .provenance) ?? .model
        preparation = try container.decodeIfPresent([PreparationMethod].self, forKey: .preparation) ?? []
        sourceRef = try container.decodeIfPresent(SourceRef.self, forKey: .sourceRef)
        alternatives = try container.decodeIfPresent([FoodAlternative].self, forKey: .alternatives) ?? []
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        sizes = try container.decodeIfPresent([FoodSize].self, forKey: .sizes) ?? []
    }

    /// The same food at a different weight. Composition is a property of the
    /// food, so it rides along untouched.
    public func weighing(_ newGrams: Double) -> MealItem {
        var copy = self
        copy.grams = newGrams
        return copy
    }

    /// Swap in one of the alternatives the model offered.
    ///
    /// The composition always changes, which is the entire point of carrying it
    /// on the alternative. The weight changes only when the alternative brought
    /// one: a rival menu item has its own size, while a loose food renamed from
    /// "chicken" to "fried chicken" is still the portion that was on the plate.
    public func choosing(_ alternative: FoodAlternative) -> MealItem {
        var copy = self
        copy.label = alternative.label
        copy.per100g = alternative.per100g
        if let grams = alternative.grams { copy.grams = grams }
        copy.provenance = .model
        copy.sourceRef = nil
        // The shortlist answered a question that has now been answered, and the
        // sizes belonged to the item that is no longer here.
        copy.alternatives = []
        copy.sizes = []
        return copy
    }

    /// The same menu item in one of the sizes its chain sells.
    ///
    /// Both figures move together, because a size is a different product rather
    /// than a scaled one — a Footlong is not a 6-inch times two once the bread
    /// ends are counted, and the chain says so itself where it publishes both.
    /// The shortlist survives: which sub it is and how big it was are separate
    /// questions, and answering one does not answer the other.
    public func resized(to size: FoodSize) -> MealItem {
        var copy = self
        copy.grams = size.grams
        copy.per100g = size.per100g
        copy.provenance = .model
        copy.sourceRef = nil
        return copy
    }
}

/// A rival reading of the same food, priced and weighed.
///
/// The weight is not decoration. A tuna sub is not the size of the turkey sub
/// the model happened to name first, and pricing a swapped row at the old row's
/// weight produces a number that looks chosen and is not.
public struct FoodAlternative: Codable, Sendable, Hashable {
    public var label: String
    public var per100g: Nutrients
    /// Nil on anything written before alternatives carried one, in which case
    /// the row keeps the weight it had — the v20 behaviour, and still the right
    /// answer for a loose food whose identity changed but whose portion did not.
    public var grams: Double?

    public init(label: String, per100g: Nutrients, grams: Double? = nil) {
        self.label = label
        self.per100g = per100g
        self.grams = grams
    }

    private enum CodingKeys: String, CodingKey {
        case label, grams
        case per100g = "per_100g"
    }
}

/// One of the sizes a chain sells a menu item in.
///
/// A size is a different product, never a multiplier. v17 deleted a
/// "A little / Normal / A lot" control because it moved no number on a weighed
/// dish, and a control that looks live and changes nothing is worse than an
/// absent one. This is the opposite shape: each size carries its own weight and
/// its own composition, so choosing one replaces the row rather than scaling it.
public struct FoodSize: Codable, Sendable, Hashable, Identifiable {
    /// The chain's own word, in the market's own language: "Footlong", "L",
    /// "並盛", "Grande".
    public var label: String
    public var grams: Double
    public var per100g: Nutrients
    /// `published` when the chain prints figures for this size, `derived` when
    /// they are arithmetic on another — a Subway Footlong is twice a Regular
    /// and nobody prints it, which makes it the size most likely to be wrong.
    public var basis: String

    public var id: String { label }

    public init(label: String, grams: Double, per100g: Nutrients, basis: String = "published") {
        self.label = label
        self.grams = grams
        self.per100g = per100g
        self.basis = basis
    }

    public var isDerived: Bool { basis == "derived" }

    private enum CodingKeys: String, CodingKey {
        case label, grams, basis
        case per100g = "per_100g"
    }
}

public enum MealSource: String, Codable, Sendable {
    case photo
    case manual
    /// Logged from a saved `Recipe`. Worth distinguishing from `manual`: a
    /// recipe entry is a repeat of something you already checked, and it is the
    /// only source that can carry ingredients no photograph could show.
    case recipe
    /// Described in words — typed or dictated — with no photograph. When a photo
    /// *and* words arrived together the source is `photo`, because the picture is
    /// the stronger evidence and the words are the caption on it.
    case text

    /// An unknown value is a source written by a build newer than this one.
    /// Falling back beats throwing: a `MealEntry` that will not decode is a meal
    /// that silently vanishes from the projection.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MealSource(rawValue: raw) ?? .manual
    }
}

/// How much of what is in the photograph you actually ate.
///
/// A platter of fruit, a shared mezze, a batch of cooking: the camera sees the
/// dish, not the serving. Without this, every communal plate inflates the
/// quantities, and it does so worst exactly where weight estimates are already
/// biased — the larger the pile, the more the model overreads it.
public enum MealShare: String, Codable, Sendable, CaseIterable {
    case whole
    case part
    /// A few bites of someone else's — enough to have eaten, not enough to
    /// count as a portion. Without it the honest answer to a shared plate you
    /// picked at is "half", which is four times what it was.
    case taste

    /// Deliberately coarse. "Half of it" is a judgement a person can make from
    /// memory; "38%" is not.
    public var factor: Double {
        switch self {
        case .whole: 1.0
        case .part: 0.5
        case .taste: 0.25
        }
    }

    public var displayName: String {
        switch self {
        case .whole: "Ate it all"
        case .part: "Ate part of it"
        case .taste: "Had a taste"
        }
    }

    /// For the picker, where the three sit side by side and the question above
    /// them supplies the verb.
    public var chipName: String {
        switch self {
        case .whole: "All of it"
        case .part: "Half"
        case .taste: "A taste"
        }
    }

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MealShare(rawValue: raw) ?? .whole
    }
}

/// Immutable model-side half of an automatically collected eval pair. The
/// enclosing `MealEntry.dishes` is the final human-confirmed half.
public struct MealRecognitionEvidence: Codable, Sendable, Hashable {
    public let promptVersion: String
    /// Which generator produced the figures, so history says for itself what
    /// wrote it rather than relying on a date to imply it.
    public let model: String?
    public let rawModelJSON: String
    public let initialDishes: [MealDish]

    public init(
        promptVersion: String,
        model: String? = nil,
        rawModelJSON: String,
        initialDishes: [MealDish]
    ) {
        self.promptVersion = promptVersion
        self.model = model
        self.rawModelJSON = rawModelJSON
        self.initialDishes = initialDishes
    }
}

public struct MealEntry: Codable, Sendable, Hashable, Identifiable {
    /// The shape this entry was written in.
    ///
    /// The field whose absence caused v20's silent failure: a decoder with no
    /// version has to guess, and guessing produced `62 kcal` for a sandwich
    /// rather than an error anybody could see. A build reading a version it does
    /// not know must refuse loudly.
    public static let schemaVersion = 21

    public let id: UUID
    public var schemaVersion: Int
    public var eatenAt: EpochMillis
    /// The meal as it reads. The only stored form — v20 also kept a flattened
    /// item list because meals predated dishes, and two representations of one
    /// thing is how they come to disagree.
    public var dishes: [MealDish]
    public var source: MealSource
    /// SHA-256 of the original image bytes. Doubles as the recognition cache key,
    /// so re-submitting the same photo never costs a second API call.
    public var photoHash: String?
    /// What you told the app that the photo could not show — "fried in butter,
    /// two eggs in the batter". Sent to the model with the image and kept with
    /// the meal, because it is half the input that produced these dishes.
    public var note: String?
    /// Raw model output and pre-edit state, for prompt evaluation.
    public var recognitionEvidence: MealRecognitionEvidence?
    /// The recognition row this meal came out of, so a figure can be traced back
    /// to the exact call that produced it.
    public var recognitionID: UUID?
    public var share: MealShare?
    /// True once you have touched the result. Uncorrected model output and
    /// human-confirmed output are not the same evidence and should not be
    /// silently mixed when you later evaluate recognition quality.
    public var wasCorrected: Bool
    /// The saved dish this meal came from, when it came from one. It is what
    /// lets the dish list say "logged 6 times" from the log rather than from a
    /// counter that would drift the first time a meal was deleted.
    public var recipeID: UUID?
    /// The message in the thread this meal was read from. Nil on anything the
    /// composer did not produce, which is why nothing may depend on it.
    public var messageID: UUID?

    public init(
        id: UUID = UUIDv7.generate(),
        schemaVersion: Int = MealEntry.schemaVersion,
        eatenAt: EpochMillis,
        dishes: [MealDish],
        source: MealSource,
        photoHash: String? = nil,
        note: String? = nil,
        recognitionEvidence: MealRecognitionEvidence? = nil,
        recognitionID: UUID? = nil,
        share: MealShare? = nil,
        wasCorrected: Bool = false,
        recipeID: UUID? = nil,
        messageID: UUID? = nil
    ) {
        self.id = id
        self.schemaVersion = schemaVersion
        self.eatenAt = eatenAt
        self.dishes = dishes
        self.source = source
        self.photoHash = photoHash
        self.note = note
        self.recognitionEvidence = recognitionEvidence
        self.recognitionID = recognitionID
        self.share = share
        self.wasCorrected = wasCorrected
        self.recipeID = recipeID
        self.messageID = messageID
    }

    public var eaten: MealShare { share ?? .whole }

    /// Every food on the plate, dish structure flattened away. Computed, never
    /// stored.
    public var items: [MealItem] { dishes.flatMap(\.items) }

    /// The weight of food on the plate, before `share`.
    public var grams: Double { items.reduce(0) { $0 + $1.grams } }

    /// What you ate: every dish, then scaled by how much of it was yours.
    ///
    /// The only nutrition arithmetic in the app. There is no lookup, no
    /// fallback, and no way for this to be partial — every item carries its own
    /// figures, so a total is a total.
    public var nutrients: Nutrients {
        dishes.reduce(Nutrients.zero) { $0 + $1.nutrients }.scaled(by: eaten.factor)
    }

    /// How the five figures were arrived at, across the whole plate. A screen
    /// wanting to qualify a number asks this rather than assuming.
    public var provenance: [NutrientSource] {
        Array(Set(items.flatMap(\.provenance.sources))).sorted { $0.rawValue < $1.rawValue }
    }
}
