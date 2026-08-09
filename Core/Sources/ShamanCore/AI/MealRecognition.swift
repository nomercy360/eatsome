import Foundation

/// What we ask the model for, and the only thing we let it tell us.
///
/// No calories and no macros. Weight is the one quantity asked for, because it
/// is the one a photograph actually shows: an amount of food, not an amount of
/// "serving". Measured on 220 weighed dishes it beat the portion ladder by 11
/// points of median error and corrected a systematic under-read.
///
/// Grams are absolute — everything of that ingredient on the plate — so nothing
/// multiplies them by the dish's count afterwards. Fat, carbohydrate and
/// calories are still never requested: a weight is an observation, and those are
/// a nutrition database's answer, not a model's.
///
/// It is also the *only* quantity asked for. `portion` and `size` were requested
/// alongside grams until v17 and then always lost to them, which made the coarse
/// answer tokens spent on something nothing read — and hid, for a month, that
/// the production Gemini schema was returning no weight at all.
public struct MealRecognition: Codable, Sendable, Hashable {
    public struct Item: Codable, Sendable, Hashable {
        public let group: FoodGroup
        public let label: String?
        /// Other groups that could plausibly be right for THIS item, most likely
        /// first. Empty is the normal case and means the model was not torn.
        ///
        /// This replaced a self-reported `confidence` number. Asked to score its
        /// own certainty, a language model returns round, uncalibrated numbers —
        /// the same 0.56 on every item of a plate, whether the item is white rice
        /// or an unidentifiable meat. Asked what *else* the food could be, it is
        /// answering a question about the photograph, and the answer is directly
        /// useful: it becomes the one-tap correction.
        public let alternatives: [FoodGroup]
        /// The dish this ingredient came out of. Absent from answers produced
        /// before dishes existed, and from cache files written then.
        public let dish: String?
        /// Always nil from v17 on: the server has no arithmetic left to do. Read
        /// only so an answer cached under an older prompt still scores the way
        /// it did when it was bought.
        public let servings: Double?
        /// The edible weight of this ingredient on the plate, and the quantity.
        ///
        /// Still optional, and only for cache files written before grams were
        /// asked for — a required field would throw all of them away. Nothing
        /// the current contract returns has a nil here.
        public let grams: Double?

        public init(
            group: FoodGroup,
            label: String?,
            alternatives: [FoodGroup] = [],
            dish: String? = nil,
            servings: Double? = nil,
            grams: Double? = nil
        ) {
            self.group = group
            self.label = label
            self.alternatives = alternatives
            self.dish = dish
            self.servings = servings
            self.grams = grams
        }

        /// The alternatives that would move the MEDAS score differently than the
        /// chosen group — the only ones worth interrupting you for. Chicken read
        /// as pork is one of these. White rice read as brown rice is not: no
        /// MEDAS item scores grains at all, so the distinction costs nothing.
        public func scoreCriticalAlternatives(excludedItems: Set<Int> = []) -> [FoodGroup] {
            alternatives.filter { Medas.choiceChangesScore(group, $0, excludedItems: excludedItems) }
        }
    }

    /// The named things the model saw, when it was asked for dishes. Nil for a
    /// cache file or a build from before dishes, which is why `items` — the
    /// flattened list — remains what everything scores from.
    public struct Dish: Codable, Sendable, Hashable {
        public let name: String
        /// How many servings of this dish. A label on the weights below rather
        /// than a factor over them — the ingredients already weigh all of it.
        public let count: Int
        /// Figures transcribed from packaging, when any were printed and legible.
        public let panel: NutritionPanel?
        public let ingredients: [Item]

        public init(
            name: String,
            count: Int = 1,
            panel: NutritionPanel? = nil,
            ingredients: [Item] = []
        ) {
            self.name = name
            self.count = count
            self.panel = panel
            self.ingredients = ingredients
        }
    }

    public let items: [Item]
    public let dishes: [Dish]?
    /// True when food outside the primary, closest tray/place setting was
    /// deliberately ignored. The correction UI must ask whether it belongs to
    /// the user before saving.
    public let otherMealsVisible: Bool
    public let notes: String?

    public init(items: [Item], dishes: [Dish]? = nil, otherMealsVisible: Bool, notes: String?) {
        self.items = items
        self.dishes = dishes
        self.otherMealsVisible = otherMealsVisible
        self.notes = notes
    }

    /// The dishes as they will be stored, with the flat list derived from them
    /// by `MealDish.flattened()` and nowhere else. Nil when the answer had no
    /// dishes, in which case `asMealItems()` is the whole meal.
    public func asMealDishes() -> [MealDish]? {
        dishes.map { dishes in
            dishes.map { dish in
                MealDish(
                    name: dish.name,
                    count: dish.count,
                    panel: (dish.panel?.isEmpty ?? true) ? nil : dish.panel,
                    items: dish.ingredients.map {
                        MealItem(
                            group: $0.group,
                            label: $0.label,
                            modelAlternatives: $0.alternatives,
                            grams: $0.grams
                        )
                    }
                )
            }
        }
    }

    public func asMealItems() -> [MealItem] {
        items.map {
            MealItem(
                group: $0.group,
                label: $0.label,
                modelAlternatives: $0.alternatives,
                dish: $0.dish,
                servings: $0.servings,
                grams: $0.grams
            )
        }
    }

    // Decode the two older shapes as well — a meal-wide `confidence` (v1) and a
    // per-item one (v2) — so recognition cache files written by earlier builds
    // remain usable instead of costing a second API call.
    private enum CodingKeys: String, CodingKey {
        case items
        case dishes
        case otherMealsVisible = "other_meals_visible"
        case notes
        case legacyConfidence = "confidence"
    }

    private struct DecodedItem: Decodable {
        let group: FoodGroup
        let label: String?
        let alternatives: [FoodGroup]?
        let confidence: Double?
        let dish: String?
        /// Carried by every answer written before v17 and by none written after.
        /// Decoded and dropped: `Item` has no portion to put it in, and the point
        /// of the version is that there is one quantity. An old cache row keeps
        /// its `servings`, which is where its ladder arithmetic already landed.
        let portion: Portion?
        let servings: Double?
        let grams: Double?
    }

    /// Below this, a legacy confidence number meant "ask the human". The groups
    /// the model habitually confuses stand in for the alternatives it was never
    /// asked to name.
    private static let legacyUncertainBelow = 0.70

    private static func legacyAlternatives(for group: FoodGroup, confidence: Double?) -> [FoodGroup] {
        guard let confidence, confidence < legacyUncertainBelow else { return [] }
        return group.commonlyConfusedWith.filter { $0 != group }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyConfidence = try container.decodeIfPresent(Double.self, forKey: .legacyConfidence)
        items = try container.decode([DecodedItem].self, forKey: .items).map {
            Item(
                group: $0.group,
                label: $0.label,
                alternatives: $0.alternatives
                    ?? Self.legacyAlternatives(for: $0.group, confidence: $0.confidence ?? legacyConfidence),
                dish: $0.dish,
                // An old row that had only a portion kept its quantity in
                // `servings`; one that had neither is a serving, as it was.
                servings: $0.servings ?? ($0.grams == nil ? $0.portion?.servings : nil),
                grams: $0.grams
            )
        }
        dishes = try container.decodeIfPresent([Dish].self, forKey: .dishes)
        otherMealsVisible = try container.decodeIfPresent(Bool.self, forKey: .otherMealsVisible) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(dishes, forKey: .dishes)
        try container.encode(otherMealsVisible, forKey: .otherMealsVisible)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

/// One thing to be read: words, a photograph, or both.
///
/// This replaced an image-and-an-optional-note signature when logging became a
/// thread. The note was always framed as "what the photograph cannot show",
/// which is the right framing for a caption and the wrong one for a message that
/// *is* the whole meal — "leftover lentil soup, big bowl" is not a supplement to
/// a picture, it is the picture's replacement. Both cases are the same act now:
/// something arrives, it gets read.
///
/// Words are also the cheapest accuracy the app has, and always were. No vision
/// model recovers the eggs in French toast, because they are not in the frame.
public struct MealMessage: Sendable, Hashable {
    /// What was typed or dictated.
    public var said: String?
    /// The photograph's bytes, when there was one.
    public var imageData: Data?
    public var mimeType: String

    public init(said: String? = nil, imageData: Data? = nil, mimeType: String = "image/jpeg") {
        self.said = said
        self.imageData = imageData
        self.mimeType = mimeType
    }

    public var hasImage: Bool { imageData != nil }

    public var trimmedText: String? {
        let text = said?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }

    /// Nothing to read. Guarded at every boundary rather than trusted, because
    /// the failure it prevents is buying a model call to describe an empty
    /// plate — and getting a confident answer about one.
    public var isEmpty: Bool { !hasImage && trimmedText == nil }

    /// What a photograph-only message used to be, kept so the meaning of the
    /// existing call sites is obvious at a glance.
    public static func photo(_ data: Data, mimeType: String = "image/jpeg", said: String? = nil) -> MealMessage {
        MealMessage(said: said, imageData: data, mimeType: mimeType)
    }

    public static func words(_ said: String) -> MealMessage {
        MealMessage(said: said)
    }
}

public protocol MealRecognizer: Sendable {
    func recognize(_ message: MealMessage) async throws -> RecognitionArtifact
}

/// Exact recognition evidence retained alongside the parsed result. This is
/// what makes every human correction usable as an eval example later.
public struct RecognitionArtifact: Codable, Sendable, Hashable {
    public let recognition: MealRecognition
    public let rawModelJSON: String
    public let promptVersion: String

    public init(recognition: MealRecognition, rawModelJSON: String, promptVersion: String) {
        self.recognition = recognition
        self.rawModelJSON = rawModelJSON
        self.promptVersion = promptVersion
    }
}

public enum MealRecognizerError: Error, LocalizedError {
    case missingAPIKey
    /// A message with neither words nor a photograph. Caught before the request
    /// rather than after: an empty prompt does not return an error, it returns a
    /// confident description of a meal nobody ate.
    case emptyMessage
    case invalidEndpoint(String)
    case http(status: Int, message: String)
    case emptyResponse
    case incomplete(reason: String)
    case refused(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No API key for the selected model. Add one in Settings."
        case .emptyMessage: "There was nothing to read — no words and no photo."
        case .invalidEndpoint(let detail): "That recognition endpoint is not a valid URL: \(detail)"
        case .http(let status, let message): "OpenAI returned \(status): \(message)"
        case .emptyResponse: "The model returned no output."
        case .incomplete(let reason): "The model stopped early (\(reason))."
        case .refused(let message): "The model declined: \(message)"
        case .decoding(let detail): "Could not read the model's response: \(detail)"
        }
    }
}

public enum MealPrompt {
    // `version` and `system` live in MealPrompt+Generated.swift, produced from
    // prompts/meal-v5.md by scripts/sync-prompt.mjs. One file, two languages,
    // and a test on each side that fails when a copy falls behind.

    /// More than this and the alternatives stop being a shortlist you can tap.
    public static let maxAlternatives = 3

    public static let user = "Classify this meal."

    /// What to send when the person says the food on the other trays is theirs
    /// as well. Answering "yes" should re-read the photograph, not hand you a
    /// blank row to fill in by hand — the picture has the answer.
    public static let everythingIsMine =
        "All the food in this photograph is mine, on every tray and plate. Include all of it."

    /// What to say when there is no photograph at all — the words are the whole
    /// input, not a correction to something visible.
    public static let fromWords = "Read this description of a meal."

    /// The user's words, fenced and labelled so they read as evidence about the
    /// food rather than as further instructions.
    ///
    /// The label differs by case, and it matters. Beside a photograph the words
    /// are what the camera missed and the picture stays the primary evidence;
    /// without one they are the only evidence there is, and a prompt that still
    /// called them "what the photo cannot show" would be describing a photo that
    /// does not exist.
    public static func userMessage(for message: MealMessage) -> String {
        guard let said = message.trimmedText else {
            return message.hasImage ? user : fromWords
        }
        guard message.hasImage else {
            return """
            \(fromWords)

            What the person ate, in their own words:
            \"\"\"
            \(said)
            \"\"\"
            """
        }
        return """
        \(user)

        What the photo cannot show, from the person who ate it:
        \"\"\"
        \(said)
        \"\"\"
        """
    }

    /// What `grams` means, stated once so both provider schemas say the same
    /// thing. The "never scale it" half matters: the dish still reports a count,
    /// and a model that helpfully multiplies would be double-counting something
    /// nothing downstream divides back out.
    static let gramsDescription = """
    Edible weight of this ingredient on the plate, in grams — everything of it that is there, already including every serving present. Never scale it by the dish's count; that is not applied afterwards either. This is the only quantity asked for.
    """

    /// Strict JSON Schema for the Responses API. Every property must appear in
    /// `required` and every object must set `additionalProperties: false` —
    /// strict mode rejects the schema otherwise. The three-alternative limit is
    /// stated in the description rather than as `maxItems`: a hard cap would
    /// silently truncate a genuine four-way ambiguity, and the client already
    /// shows only the first few.
    public static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["items", "other_meals_visible", "notes"],
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["group", "grams", "label", "alternatives"],
                        "properties": [
                            "group": [
                                "type": "string",
                                "enum": FoodGroup.allCases.map(\.rawValue),
                                "description": "Your single best answer for this item."
                            ],
                            "grams": ["type": "number", "description": "\(gramsDescription)"],
                            "label": [
                                "type": ["string", "null"],
                                "description": """
                                Short human name for one food, e.g. 'grilled sardines'. Never a \
                                hedge like 'melon or pineapple' — forks belong in `alternatives`.
                                """
                            ],
                            "alternatives": [
                                "type": "array",
                                "description": """
                                Other groups that could plausibly be right for this item, most likely \
                                first, at most \(maxAlternatives). Empty when the group is obvious. \
                                Never repeat `group` here.
                                """,
                                "items": ["type": "string", "enum": FoodGroup.allCases.map(\.rawValue)]
                            ]
                        ]
                    ]
                ],
                "other_meals_visible": [
                    "type": "boolean",
                    "description": "True when food on another tray or place setting was deliberately ignored."
                ],
                "notes": [
                    "type": ["string", "null"],
                    "description": "Ambiguities worth a human glance. Null if none."
                ]
            ]
        ]
    }
}
