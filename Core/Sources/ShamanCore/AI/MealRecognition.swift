import Foundation

/// What we ask the model for, and the only thing we let it tell us.
///
/// No calories, no grams, no macros. Those are the fields where a vision model
/// is confidently wrong, and a wrong number that looks like a measurement is
/// worse than no number: you cannot tell a bad week from a bad estimate.
public struct MealRecognition: Codable, Sendable, Hashable {
    public struct Item: Codable, Sendable, Hashable {
        public let group: FoodGroup
        public let portion: Portion
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

        public init(group: FoodGroup, portion: Portion, label: String?, alternatives: [FoodGroup] = []) {
            self.group = group
            self.portion = portion
            self.label = label
            self.alternatives = alternatives
        }

        /// The alternatives that would move the MEDAS score differently than the
        /// chosen group — the only ones worth interrupting you for. Chicken read
        /// as pork is one of these. White rice read as brown rice is not: no
        /// MEDAS item scores grains at all, so the distinction costs nothing.
        public func scoreCriticalAlternatives(excludedItems: Set<Int> = []) -> [FoodGroup] {
            alternatives.filter { Medas.choiceChangesScore(group, $0, excludedItems: excludedItems) }
        }
    }

    public let items: [Item]
    /// True when food outside the primary, closest tray/place setting was
    /// deliberately ignored. The correction UI must ask whether it belongs to
    /// the user before saving.
    public let otherMealsVisible: Bool
    public let notes: String?

    public init(items: [Item], otherMealsVisible: Bool, notes: String?) {
        self.items = items
        self.otherMealsVisible = otherMealsVisible
        self.notes = notes
    }

    public func asMealItems() -> [MealItem] {
        items.map {
            MealItem(
                group: $0.group,
                portion: $0.portion,
                label: $0.label,
                modelAlternatives: $0.alternatives
            )
        }
    }

    // Decode the two older shapes as well — a meal-wide `confidence` (v1) and a
    // per-item one (v2) — so recognition cache files written by earlier builds
    // remain usable instead of costing a second API call.
    private enum CodingKeys: String, CodingKey {
        case items
        case otherMealsVisible = "other_meals_visible"
        case notes
        case legacyConfidence = "confidence"
    }

    private struct DecodedItem: Decodable {
        let group: FoodGroup
        let portion: Portion
        let label: String?
        let alternatives: [FoodGroup]?
        let confidence: Double?
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
                portion: $0.portion,
                label: $0.label,
                alternatives: $0.alternatives
                    ?? Self.legacyAlternatives(for: $0.group, confidence: $0.confidence ?? legacyConfidence)
            )
        }
        otherMealsVisible = try container.decodeIfPresent(Bool.self, forKey: .otherMealsVisible) ?? false
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(otherMealsVisible, forKey: .otherMealsVisible)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

public protocol MealRecognizer: Sendable {
    /// `note` is what the photograph cannot show, in the user's words — "fried
    /// in butter, two eggs in the batter". It is the cheapest accuracy the app
    /// has: no vision model recovers an ingredient that is not in the frame.
    func recognize(imageData: Data, mimeType: String, note: String?) async throws -> RecognitionArtifact
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
    case invalidEndpoint(String)
    case http(status: Int, message: String)
    case emptyResponse
    case incomplete(reason: String)
    case refused(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No API key for the selected model. Add one in Settings."
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
    public static let version = "meal-v4-2026-08-05"
    /// More than this and the alternatives stop being a shortlist you can tap.
    public static let maxAlternatives = 3

    public static let system = """
    You classify a photograph of a meal into Mediterranean-diet food groups for \
    a MEDAS adherence tracker.

    Rules:
    - Report food GROUPS and coarse PORTIONS only. Never estimate calories, \
      grams, or macronutrients — they are not requested and not used.
    - Portion is relative to a normal serving of that group for one adult: \
      small is about half, medium is one, large is two or more.
    - List cooking fat when there is visible evidence of it (sheen on \
      vegetables, oil pooled on a plate, a dressed salad). Olive oil is \
      routinely present and routinely invisible; report it when the evidence \
      supports it and omit it when it does not, rather than guessing either way.
    - Sauces, dressings, spreads, and dips are food, not decoration, and they \
      are the main carrier of fat in street food. Check for them explicitly on \
      every plate: garlic and yoghurt sauces, chilli and tomato sauces, \
      mayonnaise and creamy dressings, butter or cream cheese on bread, oil \
      drizzled over a salad. Report each by what it is made of — mayonnaise and \
      cream-based dressings as butter, oil-based dressings as olive_oil, cooked \
      tomato-and-onion sauces as sofrito, yoghurt sauces as dairy.
    - Avocado, olives, seeds, and tahini are `healthy_fats`, never fruit or \
      vegetables. Nuts keep their own group.
    - Alcohol-free beer or wine is not `wine`. Report it as `other`, or omit it, \
      and say which you saw in `notes`.
    - Separate a composite dish into its groups: a grain bowl with chickpeas and \
      greens is whole_grains plus legumes plus vegetables, not one entry.
    - If multiple trays or place settings are visible, report ONLY the one \
      closest to the camera. Ignore food on every other tray or place setting \
      and set `other_meals_visible` to true whenever you skip any of it. The \
      exception is when the person tells you the rest is theirs too: then \
      include every tray and plate in the frame and set `other_meals_visible` \
      to false.
    - Inspect every bowl, cup, and small side dish on the closest place setting. \
      Soups, broths, stews, sauces, and other liquid foods are separate items, \
      not background. Decompose their visible or strongly implied ingredients; \
      for example, miso soup contains legumes. Plain water and unsweetened tea \
      need not produce a scored item.
    - The user may add a line about what the photograph cannot show — the fat a \
      dish was cooked in, eggs and milk in a batter, sugar in a sauce. Treat it \
      as ground truth about ingredients, above your own reading of the image, \
      and report those items even though they are invisible. It corrects what \
      is there; it does not remove what you can plainly see.
    - `pastry` means commercially produced baked goods. Use it only with visible \
      evidence of a manufactured item — packaging, wrapper, uniform machine \
      shaping. Something cooked at home is never `pastry`, however sweet.
    - `group` is always your single best answer. Never leave it to the user to \
      choose when you have an opinion.
    - Every item carries `alternatives`: the other food groups that could \
      plausibly be right for THAT item, most likely first, at most three. Leave \
      it EMPTY whenever the group is clear from the photo — an empty list is the \
      normal case, and flagging every item is the same as flagging none. Do not \
      report certainty as a number and do not spread one item's doubt across the \
      others.
    - Fish and white meat look alike under sauce, and so do pork and chicken. \
      When you genuinely cannot tell, put your best guess in `group`, the rival \
      in `alternatives`, and say what you were looking at in `notes`.
    - `label` is a short human name for ONE food, for the correction sheet. \
      Never hedge inside it: "sliced melon or pineapple" is not a label. Pick \
      the more likely food, name it, and put any real fork in `alternatives`.
    """

    public static let user = "Classify this meal."

    /// What to send when the person says the food on the other trays is theirs
    /// as well. Answering "yes" should re-read the photograph, not hand you a
    /// blank row to fill in by hand — the picture has the answer.
    public static let everythingIsMine =
        "All the food in this photograph is mine, on every tray and plate. Include all of it."

    /// The user's note, fenced and labelled so it reads as evidence about the
    /// food rather than as further instructions.
    public static func userMessage(note: String?) -> String {
        guard let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty else {
            return user
        }
        return """
        \(user)

        What the photo cannot show, from the person who ate it:
        \"\"\"
        \(note)
        \"\"\"
        """
    }

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
                        "required": ["group", "portion", "label", "alternatives"],
                        "properties": [
                            "group": [
                                "type": "string",
                                "enum": FoodGroup.allCases.map(\.rawValue),
                                "description": "Your single best answer for this item."
                            ],
                            "portion": ["type": "string", "enum": Portion.allCases.map(\.rawValue)],
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
