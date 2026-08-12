import Foundation

/// What we ask the model for, and the only thing we let it tell us.
///
/// Two numbers per food and nothing else: the weight on the plate, and the
/// composition per 100 g of that food. v20 asked only for weight and looked the
/// composition up in a table shipped with the app; measured against the table's
/// own sourced rows, the model reproduces published composition at 0–3% median
/// error, while the lookup left 78% of logged grams unresolved because a free
/// text label rarely matches a table key. See `Backend/eval/composition-recall-poc.ts`.
///
/// Weight is still the load-bearing figure and still the hard one — a photograph
/// shows an amount of food, and that is where the error lives. Composition is a
/// food database's answer, and the model has evidently read the database.
///
/// Grams are absolute — everything of that ingredient present, across every
/// serving — so nothing multiplies them by the dish count afterwards.
public struct MealRecognition: Codable, Sendable, Hashable {
    public struct Item: Codable, Sendable, Hashable {
        /// The food, in words. Required: it is the whole identity now.
        public let label: String
        /// The edible weight present, across every serving.
        public let grams: Double
        /// Composition per 100 g of this food, as prepared.
        public let per100g: Nutrients
        public let preparation: [PreparationMethod]
        /// Rival readings, each priced, so answering the one question the
        /// sentence raises is a local swap rather than another call.
        public let alternatives: [FoodAlternative]

        public init(
            label: String,
            grams: Double,
            per100g: Nutrients,
            preparation: [PreparationMethod] = [],
            alternatives: [FoodAlternative] = []
        ) {
            self.label = label
            self.grams = grams
            self.per100g = per100g
            self.preparation = preparation
            self.alternatives = alternatives
        }

        private enum CodingKeys: String, CodingKey {
            case label, grams, preparation, alternatives
            case per100g = "per_100g"
        }
    }

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

    public let dishes: [Dish]

    public init(dishes: [Dish]) {
        self.dishes = dishes
    }

    /// The meal as it will be stored.
    ///
    /// A printed panel is a fact about the item in front of the camera, so the
    /// figures it settled are marked `panel` and the rest stay `model`. That is
    /// the whole of the provenance decision at recognition time; `published` and
    /// `user` arrive later, from grounding and from corrections.
    public func asMealDishes() -> [MealDish] {
        dishes.map { dish in
            let panel = (dish.panel?.isEmpty ?? true) ? nil : dish.panel
            let stored = MealDish(
                name: dish.name.isEmpty ? nil : dish.name,
                count: dish.count,
                panel: panel,
                items: dish.ingredients.map {
                    MealItem(
                        label: $0.label,
                        grams: $0.grams,
                        per100g: $0.per100g,
                        provenance: .model,
                        preparation: $0.preparation,
                        alternatives: $0.alternatives
                    )
                }
            )
            guard let sources = stored.panelSources else { return stored }
            var marked = stored
            marked.items = stored.items.map {
                var item = $0
                item.provenance = sources
                return item
            }
            return marked
        }
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
        let composition: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
            "description": "Composition per 100 g of edible portion, as prepared. Never for the stated weight.",
            "properties": [
                "protein": ["type": "number", "description": "Grams per 100 g."],
                "fat": ["type": "number", "description": "Grams per 100 g."],
                "carbohydrate": ["type": "number", "description": "Grams per 100 g."],
                "kcal": ["type": "number", "description": "Kilocalories per 100 g."],
                "sodium_mg": ["type": "number", "description": "Milligrams per 100 g."]
            ]
        ]
        let alternative: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["label", "per_100g"],
            "properties": [
                "label": ["type": "string"],
                "per_100g": composition
            ]
        ]
        let ingredient: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["label", "grams", "per_100g", "preparation", "alternatives"],
            "properties": [
                "label": ["type": "string", "description": "Short, specific food name. Required — it is the whole identity."],
                "grams": ["type": "number", "description": gramsDescription],
                "per_100g": composition,
                "preparation": [
                    "type": "array",
                    "items": ["type": "string", "enum": PreparationMethod.allCases.map(\.rawValue)]
                ],
                "alternatives": [
                    "type": "array",
                    "description": "Other plausible foods, most likely first, each priced. Empty when obvious. At most three.",
                    "items": alternative
                ]
            ]
        ]
        let nullableNumber: [String: Any] = ["type": ["number", "null"]]
        let panel: [String: Any] = [
            "type": ["object", "null"],
            "additionalProperties": false,
            "required": [
                "protein", "calories", "fat", "carbohydrate", "salt", "sodium",
                "caffeine", "basis", "net_ml", "net_g"
            ],
            "properties": [
                "protein": nullableNumber, "calories": nullableNumber,
                "fat": nullableNumber, "carbohydrate": nullableNumber,
                "salt": nullableNumber, "sodium": nullableNumber,
                "caffeine": nullableNumber,
                "basis": [
                    "type": ["string", "null"],
                    "enum": ["per_100ml", "per_100g", "per_serving", "per_container", NSNull()] as [Any]
                ],
                "net_ml": nullableNumber, "net_g": nullableNumber
            ]
        ]
        return [
            "type": "object",
            "additionalProperties": false,
            "required": ["dishes"],
            "properties": [
                "dishes": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["name", "count", "panel", "ingredients"],
                        "properties": [
                            "name": ["type": "string"],
                            "count": ["type": "integer"],
                            "panel": panel,
                            "ingredients": ["type": "array", "items": ingredient]
                        ]
                    ]
                ]
            ]
        ]
    }
}
