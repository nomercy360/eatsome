import Foundation

public struct MealItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var kind: FoodKind
    public var preparation: [PreparationMethod]
    public var compositionHints: [CompositionHint]
    /// How much of it there was, coarsely. Nothing sets this any more — no model
    /// is asked for one and no screen offers one — but it stays required and
    /// stays stored, because it is on every line of `events.jsonl` written
    /// before v17 and the log is append-only. New items take `.medium` and use
    /// `grams`; old ones use this, exactly as they always did.
    public var portion: Portion
    /// Free text from the model ("grilled sardines"). Never quantified — it exists
    /// so the correction sheet can show you what the model thought it saw.
    public var label: String?
    /// The other groups the model said this could have been. Nil for manual
    /// items and for items whose group was later changed by a human — once you
    /// have decided, the model's shortlist describes a different question.
    /// Empty means the model was asked and had no rival in mind.
    public var modelAlternatives: [FoodAlternative]?
    /// How this food was (or was not) connected to a composition record.
    /// Nil on events from before provenance existed.
    public var resolution: NutrientResolution?
    /// The dish this came out of, when recognition named one. Nil on every meal
    /// logged before dishes existed, which is why nothing may depend on it.
    public var dish: String?
    /// What this contributes, when a dish supplied a count and a size that
    /// `portion` alone cannot express — three beers is 3.0 servings and no case
    /// of `Portion` says three. Nil means the portion is the whole story, which
    /// is true of every meal in the log written before dishes.
    public var servings: Double?
    /// The edible weight of this ingredient on the plate, when recognition
    /// estimated one. Absolute: everything of it that is there, not its share
    /// of one serving of a dish, so nothing multiplies it afterwards.
    ///
    /// Optional because every line written before grams existed has none, and
    /// a required field would stop the whole log decoding.
    public var grams: Double?

    /// The effective serving count. One place, so no caller has to remember which of
    /// the three fields is authoritative.
    ///
    /// Grams win when they exist: they are the closest thing to an observation,
    /// where `servings` is arithmetic done upstream and `portion` is a bucket.
    /// Then the flattened `servings`, then the portion the picker offers.
    public func effectiveServings(servingGrams: [String: Double] = ServingWeight.defaultGrams) -> Double {
        if let grams { return ServingWeight.servings(fromGrams: grams, of: kind, table: servingGrams) }
        return servings ?? portion.servings
    }

    /// The ingredient as it belongs inside a dish: its own share of one
    /// serving, with the dish's own quantity stripped back off. Flattening
    /// multiplied them in, and storing the product inside the dish as well
    /// would apply it twice the next time the dish is flattened.
    public func withoutDishQuantity() -> MealItem {
        MealItem(
            id: id,
            kind: kind,
            portion: portion,
            label: label,
            modelAlternatives: modelAlternatives,
            preparation: preparation,
            compositionHints: compositionHints,
            resolution: resolution,
            grams: grams
        )
    }

    public init(
        id: UUID = UUIDv7.generate(),
        kind: FoodKind,
        portion: Portion = .medium,
        label: String? = nil,
        modelAlternatives: [FoodAlternative]? = nil,
        preparation: [PreparationMethod] = [],
        compositionHints: [CompositionHint] = [],
        resolution: NutrientResolution? = nil,
        dish: String? = nil,
        servings: Double? = nil,
        grams: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.portion = portion
        self.label = label
        self.modelAlternatives = modelAlternatives
        self.preparation = preparation
        self.compositionHints = compositionHints
        self.resolution = resolution
        self.dish = dish
        self.servings = servings
        self.grams = grams
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, group, portion, label, modelAlternatives
        case preparation, compositionHints, resolution, dish, servings, grams
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        // TAXONOMY_BRIDGE_REMOVE_AFTER_V20_AUDIT: legacy `group` is decode-only.
        kind = try values.decodeIfPresent(FoodKind.self, forKey: .kind)
            ?? values.decode(FoodKind.self, forKey: .group)
        portion = try values.decodeIfPresent(Portion.self, forKey: .portion) ?? .medium
        label = try values.decodeIfPresent(String.self, forKey: .label)
        if let structured = try? values.decodeIfPresent([FoodAlternative].self, forKey: .modelAlternatives) {
            modelAlternatives = structured
        } else if let legacy = try? values.decodeIfPresent([FoodKind].self, forKey: .modelAlternatives) {
            modelAlternatives = legacy.map { FoodAlternative(label: $0.displayName, kind: $0) }
        } else {
            modelAlternatives = nil
        }
        preparation = try values.decodeIfPresent([PreparationMethod].self, forKey: .preparation) ?? []
        compositionHints = try values.decodeIfPresent([CompositionHint].self, forKey: .compositionHints) ?? []
        resolution = try values.decodeIfPresent(NutrientResolution.self, forKey: .resolution)
        dish = try values.decodeIfPresent(String.self, forKey: .dish)
        servings = try values.decodeIfPresent(Double.self, forKey: .servings)
        grams = try values.decodeIfPresent(Double.self, forKey: .grams)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(kind, forKey: .kind)
        try values.encode(portion, forKey: .portion)
        try values.encodeIfPresent(label, forKey: .label)
        try values.encodeIfPresent(modelAlternatives, forKey: .modelAlternatives)
        try values.encode(preparation, forKey: .preparation)
        try values.encode(compositionHints, forKey: .compositionHints)
        try values.encodeIfPresent(resolution, forKey: .resolution)
        try values.encodeIfPresent(dish, forKey: .dish)
        try values.encodeIfPresent(servings, forKey: .servings)
        try values.encodeIfPresent(grams, forKey: .grams)
    }
}

public enum MealSource: String, Codable, Sendable {
    case photo
    case manual
    /// Logged from a saved `Recipe`. Worth distinguishing from `manual`: a
    /// recipe entry is a repeat of something you already checked, and it is the
    /// only source that can carry ingredients no photograph could show.
    case recipe
    /// Described in words — typed or dictated — with no photograph.
    ///
    /// Worth its own case rather than folding into `manual`: `manual` meant a
    /// list assembled from pickers, with no model involved and no evidence
    /// worth keeping. This is a recognition like any other, and the words that
    /// produced it are on the message. When a photo *and* words arrived
    /// together the source is `photo`, because the picture is the stronger
    /// evidence and the words are the caption on it.
    case text

    /// An unknown value is a source written by a build newer than this one.
    /// Falling back beats throwing, for the same reason `MealShare` does it: a
    /// `MealEntry` that will not decode is a meal that silently vanishes from
    /// the projection, and a wrong provenance label is a far smaller loss than
    /// a missing meal.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MealSource(rawValue: raw) ?? .manual
    }
}

/// How much of what is in the photograph you actually ate.
///
/// A platter of fruit, a shared mezze, a batch of cooking: the camera sees the
/// dish, not the serving. Without this, every communal plate inflates the
/// quantities, and it does so worst exactly where portion estimates are already
/// biased — the larger the pile, the more the model overreads it.
public enum MealShare: String, Codable, Sendable, CaseIterable {
    case whole
    case part
    /// A few bites of someone else's — enough to have eaten, not enough to
    /// count as a portion. Without it the honest answer to a shared plate you
    /// picked at is "half", which is four times what it was.
    case taste

    /// Deliberately coarse, like `Portion`. "Half of it" is a judgement a person
    /// can make from memory; "38%" is not.
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

    /// An unknown value is a share written by a build newer than this one.
    /// Falling back beats throwing: a `MealEntry` that will not decode is a meal
    /// that silently vanishes from the projection, and `whole` errs toward
    /// counting what was eaten rather than losing it.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MealShare(rawValue: raw) ?? .whole
    }
}

/// Shared serving arithmetic for meal summaries.
///
/// Kept here so every consumer applies the same per-meal kind cap.
public enum MealPortions {
    /// The most any single meal can contribute for one food kind, in servings.
    ///
    /// Recognition splits a dish into as many rows as it sees — `cherry tomato`
    /// and `side salad`, or four kinds of fruit on one platter — and that is the
    /// right behaviour for the correction sheet: you can see what was actually
    /// recognized. A summary should still treat one meal as one eating occasion,
    /// worth at most one large portion of any one group.
    public static let perMealGroupCap = Portion.large.servings
}

/// Immutable model-side half of an automatically collected eval pair. The
/// enclosing `MealEntry.items` is the final human-confirmed half.
public struct MealRecognitionEvidence: Codable, Sendable, Hashable {
    public let promptVersion: String
    public let rawModelJSON: String
    public let initialItems: [MealItem]
    public let otherMealsVisible: Bool

    public init(
        promptVersion: String,
        rawModelJSON: String,
        initialItems: [MealItem],
        otherMealsVisible: Bool
    ) {
        self.promptVersion = promptVersion
        self.rawModelJSON = rawModelJSON
        self.initialItems = initialItems
        self.otherMealsVisible = otherMealsVisible
    }
}

public struct MealEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var eatenAt: EpochMillis
    public var items: [MealItem]
    public var source: MealSource
    /// SHA-256 of the original image bytes. Doubles as the recognition cache key,
    /// so re-submitting the same photo never costs a second API call.
    public var photoHash: String?
    /// Legacy meal-wide confidence retained only so existing logs decode.
    /// Recognition no longer reports certainty as a number; it names the groups
    /// an item could have been instead. Always nil on new entries.
    public var modelConfidence: Double?
    /// What you told the app that the photo could not show — "fried in butter,
    /// two eggs in the batter". Sent to the model with the image and kept with
    /// the meal, because it is half the input that produced these items.
    public var note: String?
    /// Raw model output and normalized pre-edit state for prompt evaluation.
    public var recognitionEvidence: MealRecognitionEvidence?
    /// Nil on entries written before the switch existed. Read through `eaten`,
    /// which treats absence as `.whole` — the behaviour those entries were
    /// interpreted with when they were logged.
    public var share: MealShare?
    /// True once you have touched the result. Uncorrected model output and
    /// human-confirmed output are not the same evidence and should not be
    /// silently mixed when you later evaluate recognition quality.
    public var wasCorrected: Bool
    /// The saved dish this meal came from, when it came from one. Optional
    /// because every line written before the recipe list existed has to keep
    /// decoding, and nil on anything photographed or entered by hand.
    ///
    /// It is what lets the dish list say "logged 6 times" from the log rather
    /// than from a counter that would drift the first time a meal was deleted.
    public var recipeID: UUID?
    /// The meal as it reads, when recognition named dishes. Nil on every entry
    /// written before dishes existed and on anything assembled by hand. `items`
    /// remains the list calculations use, so a build that has never heard of a
    /// dish still reads an old meal and a new one alike.
    ///
    /// When this is present, `items` is `dishes.flatMap(\.flattened())` and
    /// nothing else — `MealDish.flattened()` is the only thing that writes it.
    public var storedDishes: [MealDish]?
    /// The message in the thread this meal was read from.
    ///
    /// Nil on everything logged before the thread existed, and on anything the
    /// composer did not produce — which is why nothing may depend on it being
    /// there. It is what glues a card under its own bubble even when three
    /// messages are being read at once and finish out of order.
    public var messageID: UUID?

    public init(
        id: UUID = UUIDv7.generate(),
        eatenAt: EpochMillis,
        items: [MealItem],
        source: MealSource,
        photoHash: String? = nil,
        modelConfidence: Double? = nil,
        note: String? = nil,
        recognitionEvidence: MealRecognitionEvidence? = nil,
        share: MealShare? = nil,
        wasCorrected: Bool = false,
        recipeID: UUID? = nil,
        storedDishes: [MealDish]? = nil,
        messageID: UUID? = nil
    ) {
        self.id = id
        self.eatenAt = eatenAt
        self.items = items
        self.source = source
        self.photoHash = photoHash
        self.modelConfidence = modelConfidence
        self.note = note
        self.recognitionEvidence = recognitionEvidence
        self.share = share
        self.wasCorrected = wasCorrected
        self.recipeID = recipeID
        self.storedDishes = storedDishes
        self.messageID = messageID
    }

    public var eaten: MealShare { share ?? .whole }

    /// What this meal contributes for one group: the plate, capped
    /// at one large portion per group, then scaled by how much of it you ate.
    public func servings(
        of kind: FoodKind,
        servingGrams: [String: Double] = ServingWeight.defaultGrams
    ) -> Double {
        min(rawServings(of: kind, servingGrams: servingGrams), MealPortions.perMealGroupCap)
            * eaten.factor
    }

    /// What is on the plate, before either rule applies. This is the number to
    /// show next to the food; `servings(of:)` applies the per-meal cap.
    public func rawServings(
        of kind: FoodKind,
        servingGrams: [String: Double] = ServingWeight.defaultGrams
    ) -> Double {
        items.filter { $0.kind == kind }
            .reduce(0) { $0 + $1.effectiveServings(servingGrams: servingGrams) }
    }

    /// The meal as it reads: the dish names in the order recognition gave them,
    /// each with the ingredients that belong to it. Items from before dishes
    /// existed, and anything added by hand, come back under a nil name.
    public var dishGroups: [(name: String?, items: [MealItem])] {
        var order: [String?] = []
        var grouped: [String?: [MealItem]] = [:]
        for item in items {
            if grouped[item.dish] == nil { order.append(item.dish) }
            grouped[item.dish, default: []].append(item)
        }
        return order.map { (name: $0, items: grouped[$0] ?? []) }
    }
}
