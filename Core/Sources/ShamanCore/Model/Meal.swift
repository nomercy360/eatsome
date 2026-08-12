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

    public init(
        id: UUID = UUIDv7.generate(),
        label: String,
        grams: Double,
        per100g: Nutrients,
        provenance: NutrientProvenance = .model,
        preparation: [PreparationMethod] = [],
        sourceRef: SourceRef? = nil,
        alternatives: [FoodAlternative] = []
    ) {
        self.id = id
        self.label = label
        self.grams = grams
        self.per100g = per100g
        self.provenance = provenance
        self.preparation = preparation
        self.sourceRef = sourceRef
        self.alternatives = alternatives
    }

    /// What this item contributes. Arithmetic on two stored values — not a
    /// lookup into anything that can change underneath it.
    public var nutrients: Nutrients { per100g.forGrams(grams) }

    /// `per_100g` on the wire and on disk, matching the recognition contract and
    /// `Backend/src/contracts.ts`. One spelling everywhere: the alternative is a
    /// type whose stored shape differs from the shape it arrived in, which is a
    /// mismatch nothing would catch until a round trip lost a figure.
    private enum CodingKeys: String, CodingKey {
        case id, label, grams, provenance, preparation, sourceRef, alternatives
        case per100g = "per_100g"
    }

    /// The same food at a different weight. Composition is a property of the
    /// food, so it rides along untouched.
    public func weighing(_ newGrams: Double) -> MealItem {
        var copy = self
        copy.grams = newGrams
        return copy
    }

    /// Swap in one of the alternatives the model offered. The weight is what was
    /// on the plate and does not change because the food was renamed; the
    /// composition does, which is the entire point of carrying it on the
    /// alternative.
    public func choosing(_ alternative: FoodAlternative) -> MealItem {
        var copy = self
        copy.label = alternative.label
        copy.per100g = alternative.per100g
        copy.provenance = .model
        copy.sourceRef = nil
        // The shortlist answered a question that has now been answered.
        copy.alternatives = []
        return copy
    }
}

/// A rival reading of the same food, priced.
public struct FoodAlternative: Codable, Sendable, Hashable {
    public var label: String
    public var per100g: Nutrients

    public init(label: String, per100g: Nutrients) {
        self.label = label
        self.per100g = per100g
    }

    private enum CodingKeys: String, CodingKey {
        case label
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
