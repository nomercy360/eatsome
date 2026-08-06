import Foundation

public struct MealItem: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var group: FoodGroup
    public var portion: Portion
    /// Free text from the model ("grilled sardines"). Never scored — it exists
    /// so the correction sheet can show you what the model thought it saw.
    public var label: String?
    /// The other groups the model said this could have been. Nil for manual
    /// items and for items whose group was later changed by a human — once you
    /// have decided, the model's shortlist describes a different question.
    /// Empty means the model was asked and had no rival in mind.
    public var modelAlternatives: [FoodGroup]?
    /// The dish this came out of, when recognition named one. Nil on every meal
    /// logged before dishes existed, which is why nothing may depend on it.
    public var dish: String?
    /// What this contributes, when a dish supplied a count and a size that
    /// `portion` alone cannot express — three beers is 3.0 servings and no case
    /// of `Portion` says three. Nil means the portion is the whole story, which
    /// is true of every meal in the log written before dishes.
    public var servings: Double?

    /// The number that scores. One place, so no caller has to remember which of
    /// the two fields is authoritative.
    public var effectiveServings: Double { servings ?? portion.servings }

    /// The ingredient as it belongs inside a dish: its own share of one
    /// serving, with the dish's count and size stripped back off. Flattening
    /// multiplied them in, and storing the product inside the dish as well
    /// would apply it twice the next time the dish is flattened.
    public func withoutDishQuantity() -> MealItem {
        MealItem(
            id: id,
            group: group,
            portion: portion,
            label: label,
            modelAlternatives: modelAlternatives
        )
    }

    public init(
        id: UUID = UUIDv7.generate(),
        group: FoodGroup,
        portion: Portion,
        label: String? = nil,
        modelAlternatives: [FoodGroup]? = nil,
        dish: String? = nil,
        servings: Double? = nil
    ) {
        self.id = id
        self.group = group
        self.portion = portion
        self.label = label
        self.modelAlternatives = modelAlternatives
        self.dish = dish
        self.servings = servings
    }
}

public enum MealSource: String, Codable, Sendable {
    case photo
    case manual
    /// Logged from a saved `Recipe`. Worth distinguishing from `manual`: a
    /// recipe entry is a repeat of something you already checked, and it is the
    /// only source that can carry ingredients no photograph could show.
    case recipe
}

/// How much of what is in the photograph you actually ate.
///
/// A platter of fruit, a shared mezze, a week's batch cooking: the camera sees
/// the dish, not the serving. Without this, every communal plate inflates the
/// week, and it inflates it worst exactly where portion estimates are already
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

/// How a plate becomes a number.
///
/// Kept here rather than inside the scorer so the rule has one home and the UI
/// can quote it.
public enum MealScoring {
    /// The most any single meal can contribute for one food group, in servings.
    ///
    /// Recognition splits a dish into as many rows as it sees — `cherry tomato`
    /// and `side salad`, or four kinds of fruit on one platter — and that is the
    /// right behaviour for the correction sheet: you can see what was actually
    /// recognized. It is the wrong behaviour for the score, where four fruit
    /// rows would clear a daily target from a single photograph. One meal is one
    /// eating occasion, worth at most one large portion of any one group.
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
    /// scored with when they were logged.
    public var share: MealShare?
    /// True once you have touched the result. Uncorrected model output and
    /// human-confirmed output are not the same evidence and should not be
    /// silently mixed when you later look at why a week scored badly.
    public var wasCorrected: Bool
    /// The saved dish this meal came from, when it came from one. Optional
    /// because every line written before the recipe list existed has to keep
    /// decoding, and nil on anything photographed or entered by hand.
    ///
    /// It is what lets the dish list say "logged 6 times" from the log rather
    /// than from a counter that would drift the first time a meal was deleted.
    public var recipeID: UUID?
    /// The meal as it reads, when recognition named dishes. Nil on every entry
    /// written before dishes existed and on anything assembled by hand, which
    /// is why `items` remains the list the score is computed from: a build that
    /// has never heard of a dish still scores an old meal and a new one alike.
    ///
    /// When this is present, `items` is `dishes.flatMap(\.flattened())` and
    /// nothing else — `MealDish.flattened()` is the only thing that writes it.
    public var storedDishes: [MealDish]?

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
        storedDishes: [MealDish]? = nil
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
    }

    public var eaten: MealShare { share ?? .whole }

    /// What this meal contributes to the week for one group: the plate, capped
    /// at one large portion per group, then scaled by how much of it you ate.
    public func servings(of group: FoodGroup) -> Double {
        min(rawServings(of: group), MealScoring.perMealGroupCap) * eaten.factor
    }

    /// What is on the plate, before either rule applies. This is the number to
    /// show next to the food; `servings(of:)` is the number that scores.
    public func rawServings(of group: FoodGroup) -> Double {
        items.filter { $0.group == group }.reduce(0) { $0 + $1.effectiveServings }
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
