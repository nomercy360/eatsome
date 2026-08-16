import Foundation

/// How much of a thing was actually had.
public enum MealShare: String, Codable, Sendable, Hashable, CaseIterable {
    case whole
    case part
    case taste

    public var factor: Double {
        switch self {
        case .whole: 1
        case .part: 0.5
        case .taste: 0.15
        }
    }

    public var chipName: String {
        switch self {
        case .whole: "All of it"
        case .part: "Half"
        case .taste: "A taste"
        }
    }
}

/// Where a meal came from. `text` and `photo` differ by what evidence the model
/// had, which is worth keeping: when a photo *and* words arrive together the
/// source is `photo`, because the picture is the stronger evidence and the words
/// are the caption on it.
public enum MealSource: String, Codable, Sendable, Hashable {
    case photo
    case text
    case manual
}

/// One food, and the whole of what the app knows about it.
///
/// `label` is the entire identity. No kind, no group, no code to fall back to —
/// the previous schema's composition table was keyed `kind|label` and matched
/// exactly, recognition writes free text, and 78% of logged grams resolved to
/// nothing. One food per label, and the prompt forbids "and" as well as "or",
/// because a row that names two foods cannot be priced as either.
public struct MealItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// What this food is, in words: "grilled beef", "subway bread".
    public var label: String
    /// How it was cooked, when the input said. Structured for exactly one
    /// reason: it is what lets a correction ask "grilled or fried?" with chips
    /// instead of free text. It feeds no calculation — the composition below
    /// already prices the food as prepared.
    public var preparation: [PreparationMethod]
    /// The edible weight present, across every serving. Absolute: nothing
    /// multiplies it afterwards.
    ///
    /// This is the only hard number in the schema and the only one worth
    /// arguing about. A photograph shows an amount of food; composition is a
    /// food database's answer and the model has evidently read the database.
    public var grams: Double
    /// Composition per 100 g of this food.
    ///
    /// Per 100 g rather than per portion so that changing the weight is
    /// multiplication rather than a stale number or a second round trip. It
    /// also keeps the composition claim separable from the weight claim, which
    /// matters because they fail differently and weight is where the error is.
    public var per100g: Nutrients
    /// Who supplied each figure.
    public var provenance: NutrientProvenance
    /// What else this could have been, each priced, so answering "honey or
    /// syrup?" is a local swap rather than another call. Empty means the model
    /// was asked and had no rival in mind.
    ///
    /// Each alternative carries its own composition, because a rename that
    /// cannot re-price is a silent lie: the previous picker swapped a food's
    /// *name* while a table decided its *worth*.
    public var alternatives: [FoodAlternative]
    /// The chain whose product this is, when it is one. Its presence is what
    /// makes a row a menu item rather than a food.
    public var brand: String?
    /// The sizes that brand publishes for this product, each priced.
    public var sizes: [FoodSize]

    public init(
        id: UUID = UUIDv7.generate(),
        label: String,
        preparation: [PreparationMethod] = [],
        grams: Double,
        per100g: Nutrients,
        provenance: NutrientProvenance = .model,
        alternatives: [FoodAlternative] = [],
        brand: String? = nil,
        sizes: [FoodSize] = []
    ) {
        self.id = id
        self.label = label
        self.preparation = preparation
        self.grams = grams
        self.per100g = per100g
        self.provenance = provenance
        self.alternatives = alternatives
        self.brand = brand
        self.sizes = sizes
    }

    /// `per_100g` on the wire and on disk, matching the recognition contract.
    /// One spelling everywhere: the alternative is a type whose stored shape
    /// differs from the shape it arrived in, which is a mismatch nothing would
    /// catch until a round trip lost a figure.
    private enum CodingKeys: String, CodingKey {
        case id, label, preparation, grams, provenance, alternatives, brand, sizes
        case per100g = "per_100g"
    }

    /// Whether this row is something somebody's menu lists — the question a
    /// correction screen has to answer before it decides what to offer: chips
    /// and a stepper, or a weight.
    public var isMenuItem: Bool { !(brand?.isEmpty ?? true) }

    /// What this item contributes. Arithmetic on two stored values — not a
    /// lookup into anything that can change underneath it.
    public var nutrients: Nutrients { per100g.forGrams(grams) }
}

/// A priced *and weighed* rival for a food the model was not sure about.
///
/// Both, and the weight is the half that is easy to leave out. A rival is
/// rarely the same size as the first answer — a tuna sub is not a turkey sub,
/// a spoon of honey is not a spoon of syrup — so a swap that changes
/// composition and keeps the old weight produces a figure that looks chosen and
/// is not. That is the same shape as the rename-cannot-re-price rule one level
/// down: what moves must restate everything it moves.
public struct FoodAlternative: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var label: String
    public var per100g: Nutrients
    /// Edible weight of this rival as the model weighed it — absolute, across
    /// every serving that was present, exactly as `MealItem.grams` is.
    public var grams: Double

    public init(
        id: UUID = UUIDv7.generate(),
        label: String,
        per100g: Nutrients,
        grams: Double
    ) {
        self.id = id
        self.label = label
        self.per100g = per100g
        self.grams = grams
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, grams
        case per100g = "per_100g"
    }
}

/// One size a chain publishes for a product, with the weight that size is.
public struct FoodSize: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var label: String
    public var grams: Double
    public var per100g: Nutrients

    public init(id: UUID = UUIDv7.generate(), label: String, grams: Double, per100g: Nutrients) {
        self.id = id
        self.label = label
        self.grams = grams
        self.per100g = per100g
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, grams
        case per100g = "per_100g"
    }
}

/// A printed panel, when one was visible. Every field optional because a panel
/// is routinely partial and an unreadable figure has to come back as absent
/// rather than as zero.
///
/// Figures here are for the whole dish as present, already scaled across
/// `count` — not per 100 g. A panel is a fact about a package, and the package
/// is what is on the plate.
public struct NutritionPanel: Codable, Sendable, Hashable {
    public var kcal: Double?
    public var protein: Double?
    public var fat: Double?
    public var carbohydrate: Double?
    /// Grams of salt, as non-US labels print it.
    public var salt: Double?
    /// Grams of sodium, as US labels print it.
    public var sodium: Double?
    public var alcohol: Double?
    public var caffeine: Double?

    public init(
        kcal: Double? = nil,
        protein: Double? = nil,
        fat: Double? = nil,
        carbohydrate: Double? = nil,
        salt: Double? = nil,
        sodium: Double? = nil,
        alcohol: Double? = nil,
        caffeine: Double? = nil
    ) {
        self.kcal = kcal
        self.protein = protein
        self.fat = fat
        self.carbohydrate = carbohydrate
        self.salt = salt
        self.sodium = sodium
        self.alcohol = alcohol
        self.caffeine = caffeine
    }

    public var isEmpty: Bool {
        kcal == nil && protein == nil && fat == nil && carbohydrate == nil
            && salt == nil && sodium == nil && alcohol == nil && caffeine == nil
    }
}

/// A named thing on the plate, and what it is made of.
public struct MealDish: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// What it is called. Nil for food assembled by hand that belongs to no
    /// named dish.
    public var name: String?
    /// How many servings are present. Three beers is one dish with count 3, and
    /// the ingredient weights already account for all three.
    public var count: Int
    /// How much of this one dish was had. Nil is the whole dish and is the only
    /// value recognition writes; it becomes non-nil when a mixed meal is
    /// corrected one row at a time.
    public var share: MealShare?
    /// What the packaging said, when it said anything.
    public var panel: NutritionPanel?
    public var items: [MealItem]

    public init(
        id: UUID = UUIDv7.generate(),
        name: String? = nil,
        count: Int = 1,
        share: MealShare? = nil,
        panel: NutritionPanel? = nil,
        items: [MealItem] = []
    ) {
        self.id = id
        self.name = name
        self.count = count
        self.share = share
        self.panel = panel
        self.items = items
    }

    public var grams: Double { items.reduce(0) { $0 + $1.grams } }

    /// The dish total: its ingredients summed, then any printed figure
    /// substituted in.
    ///
    /// Figure by figure rather than wholesale: a carton printing protein and
    /// energy but no sodium contributes two read numbers and the rest from the
    /// model, and discarding the ingredients over a partial panel throws away
    /// something true.
    public var nutrients: Nutrients {
        var total = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
        if let panel {
            if let value = panel.protein { total.protein = value }
            if let value = panel.fat { total.fat = value }
            if let value = panel.carbohydrate { total.carbohydrate = value }
            if let value = panel.kcal { total.kcal = value }
            if let value = panel.alcohol { total.alcohol = value }
            if let value = panel.caffeine { total.caffeine = value }
            // The panel prints grams of salt or grams of sodium;
            // `Nutrients.sodium` is milligrams. Salt is preferred when both are
            // present because it is what the label was actually counted in
            // outside the United States.
            if let salt = panel.salt {
                total.sodium = salt * 1000 / Nutrients.saltPerSodium
            } else if let sodium = panel.sodium {
                total.sodium = sodium * 1000
            }
        }
        return total.scaled(by: (share ?? .whole).factor)
    }

    /// Which figures this dish's panel settled, so a caller can mark them read
    /// rather than estimated without re-deriving the rule above.
    public var panelSources: NutrientProvenance? {
        guard let panel else { return nil }
        var sources = NutrientProvenance.model
        if panel.protein != nil { sources.protein = .panel }
        if panel.fat != nil { sources.fat = .panel }
        if panel.carbohydrate != nil { sources.carbohydrate = .panel }
        if panel.kcal != nil { sources.kcal = .panel }
        if panel.alcohol != nil { sources.alcohol = .panel }
        if panel.caffeine != nil { sources.caffeine = .panel }
        if panel.salt != nil || panel.sodium != nil { sources.sodium = .panel }
        return sources
    }

    /// The dish as if a different number of servings had been present.
    ///
    /// Rewrites the weights rather than multiplying at score time, so there is
    /// never a second place where quantity lives. The old `count × size ×
    /// portion` product is what made one bowl of ramen worth 126 g of protein.
    public func scaled(toCount newCount: Int) -> MealDish {
        let target = max(1, newCount)
        guard count > 0, target != count else {
            var copy = self
            copy.count = target
            return copy
        }
        let factor = Double(target) / Double(count)
        var copy = self
        copy.count = target
        copy.items = items.map {
            var item = $0
            item.grams *= factor
            // The shortlist scales with the food it is a shortlist *for*.
            //
            // It did not, and the drift was invisible: `grams` moved to the new
            // count while every rival stayed anchored to the count at
            // recognition, so picking one after touching the stepper swapped
            // 458 g of B.M.T. for 240 g of roast beef and called it two subs.
            // A rival that cannot be substituted at the current size is the
            // rename-cannot-re-price failure wearing a different hat.
            item.alternatives = item.alternatives.map {
                var alternative = $0
                alternative.grams *= factor
                return alternative
            }
            // `sizes` deliberately does not scale, and the symmetry is a trap.
            // A `FoodSize.grams` is a published fact about one serving of the
            // chain's product, not about this plate, and `applying(size:)`
            // multiplies it by the count where it is used. Scaling it here too
            // would square the count — which is precisely the `count × size ×
            // portion` product that made one bowl of ramen worth 126 g of
            // protein, and precisely why a size is a different product rather
            // than a multiplier.
            return item
        }
        if var panel = copy.panel {
            panel.kcal = panel.kcal.map { $0 * factor }
            panel.protein = panel.protein.map { $0 * factor }
            panel.fat = panel.fat.map { $0 * factor }
            panel.carbohydrate = panel.carbohydrate.map { $0 * factor }
            panel.salt = panel.salt.map { $0 * factor }
            panel.sodium = panel.sodium.map { $0 * factor }
            panel.alcohol = panel.alcohol.map { $0 * factor }
            panel.caffeine = panel.caffeine.map { $0 * factor }
            copy.panel = panel
        }
        return copy
    }
}

/// A meal, as stored. `dishes` is the only stored form — `items`, `grams` and
/// `nutrients` are computed, because two representations of one thing is how
/// they come to disagree.
public struct MealEntry: Codable, Sendable, Hashable, Identifiable {
    /// The shape every meal event is written in. A reader that meets another
    /// number refuses rather than guesses — the previous log had no version,
    /// guessed, and showed 62 kcal for a sandwich instead of an error anyone
    /// could see. There is no older version to read: the only installs are
    /// test accounts, so 1 is the first and only value this has ever had.
    public static let schemaVersion = 1

    public enum SchemaError: Error, Sendable, Equatable {
        case unsupportedVersion(Int)
    }

    public let id: UUID
    public var eatenAt: EpochMillis
    public var dishes: [MealDish]
    public var source: MealSource
    /// SHA-256 of the original image bytes. Doubles as the recognition cache
    /// key, so re-submitting the same photo never costs a second call.
    public var photoHash: String?
    /// What you told the app that the photo could not show — "fried in butter,
    /// two eggs in the batter". Sent to the model with the image and kept,
    /// because it is half the input that produced these dishes.
    public var note: String?
    /// Something you wrote for yourself afterwards, which is not input to
    /// anything.
    public var personalNote: String?
    public var share: MealShare?
    /// Whole-meal figures supplied by the person. They describe the complete
    /// plate before `share`, so the same share control still answers how much
    /// of that plate was theirs.
    public var nutritionOverride: Nutrients?
    /// True once you have touched the result. Uncorrected model output and
    /// human-confirmed output are not the same evidence and should not be
    /// silently mixed when you later evaluate recognition quality.
    public var wasCorrected: Bool
    /// The message this meal was read from. Nil on anything the composer did
    /// not produce, which is why nothing may depend on it.
    public var messageID: UUID?

    public init(
        id: UUID = UUIDv7.generate(),
        eatenAt: EpochMillis,
        dishes: [MealDish],
        source: MealSource,
        photoHash: String? = nil,
        note: String? = nil,
        personalNote: String? = nil,
        share: MealShare? = nil,
        nutritionOverride: Nutrients? = nil,
        wasCorrected: Bool = false,
        messageID: UUID? = nil
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.dishes = dishes
        self.source = source
        self.photoHash = photoHash
        self.note = note
        self.personalNote = personalNote
        self.share = share
        self.nutritionOverride = nutritionOverride
        self.wasCorrected = wasCorrected
        self.messageID = messageID
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, eatenAt, dishes, source, photoHash, note
        case personalNote, share, nutritionOverride, wasCorrected, messageID
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version == Self.schemaVersion else {
            throw SchemaError.unsupportedVersion(version)
        }
        id = try c.decode(UUID.self, forKey: .id)
        eatenAt = try c.decode(EpochMillis.self, forKey: .eatenAt)
        dishes = try c.decode([MealDish].self, forKey: .dishes)
        source = try c.decode(MealSource.self, forKey: .source)
        photoHash = try c.decodeIfPresent(String.self, forKey: .photoHash)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        personalNote = try c.decodeIfPresent(String.self, forKey: .personalNote)
        share = try c.decodeIfPresent(MealShare.self, forKey: .share)
        nutritionOverride = try c.decodeIfPresent(Nutrients.self, forKey: .nutritionOverride)
        wasCorrected = try c.decode(Bool.self, forKey: .wasCorrected)
        messageID = try c.decodeIfPresent(UUID.self, forKey: .messageID)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersion, forKey: .schemaVersion)
        try c.encode(id, forKey: .id)
        try c.encode(eatenAt, forKey: .eatenAt)
        try c.encode(dishes, forKey: .dishes)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(photoHash, forKey: .photoHash)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(personalNote, forKey: .personalNote)
        try c.encodeIfPresent(share, forKey: .share)
        try c.encodeIfPresent(nutritionOverride, forKey: .nutritionOverride)
        try c.encode(wasCorrected, forKey: .wasCorrected)
        try c.encodeIfPresent(messageID, forKey: .messageID)
    }

    public var eaten: MealShare { share ?? .whole }

    /// Every food on the plate, dish structure flattened away. Computed, never
    /// stored.
    public var items: [MealItem] { dishes.flatMap(\.items) }

    /// The weight of food on the plate, before `share`.
    public var grams: Double { items.reduce(0) { $0 + $1.grams } }

    /// What you ate: every dish, then scaled by how much of it was yours.
    ///
    /// The only nutrition arithmetic in the app. No lookup, no fallback, and no
    /// way for this to be partial — every item carries its own figures, so a
    /// total is a total.
    public var nutrients: Nutrients {
        (nutritionOverride ?? dishes.reduce(Nutrients.zero) { $0 + $1.nutrients })
            .scaled(by: eaten.factor)
    }

    /// How the figures were arrived at across the whole plate. A screen wanting
    /// to qualify a number asks this rather than assuming.
    public var provenance: [NutrientSource] {
        if nutritionOverride != nil { return [.user] }
        return Array(Set(items.flatMap(\.provenance.sources))).sorted { $0.rawValue < $1.rawValue }
    }
}
