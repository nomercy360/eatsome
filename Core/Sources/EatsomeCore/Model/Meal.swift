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
    /// The choices the input left open on this row — which size, which milk,
    /// which drink was in the cup — each a set of priced answers for this same
    /// food. Empty is the normal case. See `FoodFork`.
    public var forks: [FoodFork]

    public init(
        id: UUID = UUIDv7.generate(),
        label: String,
        preparation: [PreparationMethod] = [],
        grams: Double,
        per100g: Nutrients,
        provenance: NutrientProvenance = .model,
        alternatives: [FoodAlternative] = [],
        brand: String? = nil,
        forks: [FoodFork] = []
    ) {
        self.id = id
        self.label = label
        self.preparation = preparation
        self.grams = grams
        self.per100g = per100g
        self.provenance = provenance
        self.alternatives = alternatives
        self.brand = brand
        self.forks = forks
    }

    /// `per_100g` on the wire and on disk, matching the recognition contract.
    /// One spelling everywhere: the alternative is a type whose stored shape
    /// differs from the shape it arrived in, which is a mismatch nothing would
    /// catch until a round trip lost a figure.
    private enum CodingKeys: String, CodingKey {
        case id, label, preparation, grams, provenance, alternatives, brand, forks
        case per100g = "per_100g"
    }

    /// Version-one meals stored `sizes` instead of `forks`. The meal's chosen
    /// figures already live in `grams` and `per_100g`, so the retired picker
    /// metadata is deliberately ignored rather than guessed into a fork whose
    /// `chosen_from` was never recorded. New and transitional records that do
    /// contain forks still decode them normally.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        preparation = try c.decode([PreparationMethod].self, forKey: .preparation)
        grams = try c.decode(Double.self, forKey: .grams)
        per100g = try c.decode(Nutrients.self, forKey: .per100g)
        provenance = try c.decode(NutrientProvenance.self, forKey: .provenance)
        alternatives = try c.decode([FoodAlternative].self, forKey: .alternatives)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        forks = try c.decodeIfPresent([FoodFork].self, forKey: .forks) ?? []
    }

    /// The forks worth putting to the person, most consequential first.
    ///
    /// A fork is a question only when nothing in the input decided its default
    /// (`chosenFrom == .assumed`) **and** the answer would move the row by
    /// enough to be worth a tap: at least `FoodFork.askFloorKcal`, and at least
    /// `FoodFork.askShare` of the row's own energy. Measured (`Backend/eval/
    /// forks-poc.md`) that keeps a gyudon's size (Δ350–540 kcal), a Subway
    /// (Δ350), fries (Δ250), the drink in an opaque cup (Δ135–220) and a
    /// latte's size (Δ141–243), and drops the milk in a cappuccino (Δ18–63) —
    /// half the drink, and not worth interrupting anyone over in a day.
    public var openForks: [FoodFork] {
        let rowKcal = nutrients.kcal
        return forks
            .filter { $0.isOpen(rowKcal: rowKcal) }
            .sorted { $0.kcalSpread > $1.kcalSpread }
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

/// A choice the input left open on one row, as a set of priced answers.
///
/// Which size, which milk, which drink is in the cup, dressing or none: each
/// option is a complete answer for the *same* food — its own weight for the
/// whole row and its own composition — and exactly one of them is `chosen`,
/// the one the row's own figures already assume. Choosing another *replaces*
/// the row's weight and composition the way choosing an alternative replaces
/// its name: an option is a different product, never a multiplier.
///
/// This replaced `sizes`, which could say Regular/Footlong and nothing else.
/// Asked the same 14 inputs, the model put Coke/Diet Coke/Sprite (Δ220 kcal)
/// and whole/oat/non-fat milk in this shape, priced each option in full, and
/// marked the row's own answer `chosen` 81 times out of 81. `axis` is free
/// text and only ever rendered — an enum here would make a milk question wait
/// for a release.
public struct FoodFork: Codable, Sendable, Hashable, Identifiable {
    /// A fork below this many kilocalories of spread is never asked.
    public static let askFloorKcal: Double = 100
    /// Nor one whose spread is below this share of the row's own energy.
    public static let askShare: Double = 0.2

    public let id: UUID
    /// One or two lowercase words: "size", "milk", "drink".
    public var axis: String
    /// What decided the chosen option — see `ForkEvidence`.
    public var chosenFrom: ForkEvidence
    public var options: [FoodForkOption]

    public init(
        id: UUID = UUIDv7.generate(),
        axis: String,
        chosenFrom: ForkEvidence,
        options: [FoodForkOption]
    ) {
        self.id = id
        self.axis = axis
        self.chosenFrom = chosenFrom
        self.options = options
    }

    private enum CodingKeys: String, CodingKey {
        case id, axis, options
        case chosenFrom = "chosen_from"
    }

    /// The option the row's own figures assume.
    public var chosen: FoodForkOption? { options.first { $0.chosen } }

    /// How far apart the options are, in kilocalories for the whole row.
    public var kcalSpread: Double {
        let kcals = options.map { $0.per100g.forGrams($0.grams).kcal }
        guard let low = kcals.min(), let high = kcals.max() else { return 0 }
        return high - low
    }

    /// Whether this fork is a question for the person, given the row's energy.
    /// Only an assumed default is a question; a stated or seen one is kept as
    /// priced options for anyone who opens the pick sheet, and nothing more.
    public func isOpen(rowKcal: Double) -> Bool {
        chosenFrom == .assumed
            && kcalSpread >= max(Self.askFloorKcal, Self.askShare * rowKcal)
    }

    /// The fork with `option` chosen and the choice recorded as the person's.
    /// A fork the person answered is no longer a question, whatever it was
    /// before, so `chosenFrom` becomes `.stated`.
    public func choosing(_ option: FoodForkOption) -> FoodFork {
        var copy = self
        copy.chosenFrom = .stated
        copy.options = options.map {
            var next = $0
            next.chosen = $0.id == option.id
            return next
        }
        return copy
    }
}

/// What decided a fork's default.
///
/// The model was asked to leave a fork out when the input had settled it, and
/// could not: "grande oat milk latte" still came back with a size fork three
/// runs in four. Asked instead to *say* what decided the default, it was
/// right sixteen times in sixteen — a stated footlong, a size legible on the
/// cup, a drink in an opaque cup. So the app gates on this, and never on the
/// fork's presence.
public enum ForkEvidence: String, Codable, Sendable, Hashable {
    /// The person's words name it.
    case stated
    /// The photograph shows it.
    case seen
    /// Nothing did; the model took the usual one.
    case assumed
}

/// One answer to a fork, priced in full for the whole row.
public struct FoodForkOption: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// In the words the person would use, in the market's language:
    /// "Footlong", "並盛", "Grande", "oat milk", "Coke Zero".
    public var label: String
    /// Edible weight of the whole row if this option is right — absolute,
    /// across every serving present, exactly as `MealItem.grams` is.
    public var grams: Double
    public var per100g: Nutrients
    /// True on the one option the row's own figures assume.
    public var chosen: Bool

    public init(
        id: UUID = UUIDv7.generate(),
        label: String,
        grams: Double,
        per100g: Nutrients,
        chosen: Bool = false
    ) {
        self.id = id
        self.label = label
        self.grams = grams
        self.per100g = per100g
        self.chosen = chosen
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, grams, chosen
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
            // A fork's options are whole-row answers, exactly as a rival is,
            // and scale for the same reason: an option that cannot be applied
            // at the current count is the rename-cannot-re-price failure. (The
            // `sizes` this replaced were per serving and multiplied where
            // applied; scaling them here as well squared the count.)
            item.forks = item.forks.map {
                var fork = $0
                fork.options = fork.options.map {
                    var option = $0
                    option.grams *= factor
                    return option
                }
                return fork
            }
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
    /// The shape every new meal event is written in. Version one used `sizes`;
    /// version two uses `forks`. The version-one decoder keeps the meal's
    /// chosen figures and drops that obsolete picker metadata rather than
    /// inventing facts it did not store.
    public static let schemaVersion = 2

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
        guard version == 1 || version == Self.schemaVersion else {
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
