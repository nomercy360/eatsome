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
    }

    public let items: [Item]
    /// The model's own 0...1 confidence. Used to decide whether to open the
    /// correction sheet automatically, not to weight the score.
    public let confidence: Double
    public let notes: String?

    public func asMealItems() -> [MealItem] {
        items.map { MealItem(group: $0.group, portion: $0.portion, label: $0.label) }
    }
}

public protocol MealRecognizer: Sendable {
    func recognize(imageData: Data, mimeType: String) async throws -> MealRecognition
}

public enum MealRecognizerError: Error, LocalizedError {
    case missingAPIKey
    case http(status: Int, message: String)
    case emptyResponse
    case incomplete(reason: String)
    case refused(String)
    case decoding(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "No OpenAI API key. Add one in Settings."
        case .http(let status, let message): "OpenAI returned \(status): \(message)"
        case .emptyResponse: "The model returned no output."
        case .incomplete(let reason): "The model stopped early (\(reason))."
        case .refused(let message): "The model declined: \(message)"
        case .decoding(let detail): "Could not read the model's response: \(detail)"
        }
    }
}

public enum MealPrompt {
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
    - Separate a composite dish into its groups: a grain bowl with chickpeas and \
      greens is whole_grains plus legumes plus vegetables, not one entry.
    - Fish and white meat look alike under sauce. If you cannot tell, choose the \
      more likely one and say so in `notes`, and lower `confidence`.
    - `confidence` is your probability that a human would accept this breakdown \
      unchanged. Be honest and low rather than agreeable.
    - `label` is a short human name for what you saw, for the correction sheet.
    """

    public static let user = "Classify this meal."

    /// Strict JSON Schema for the Responses API. Every property must appear in
    /// `required` and every object must set `additionalProperties: false` —
    /// strict mode rejects the schema otherwise.
    public static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["items", "confidence", "notes"],
            "properties": [
                "items": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["group", "portion", "label"],
                        "properties": [
                            "group": ["type": "string", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "portion": ["type": "string", "enum": Portion.allCases.map(\.rawValue)],
                            "label": ["type": ["string", "null"], "description": "Short human name, e.g. 'grilled sardines'"]
                        ]
                    ]
                ],
                "confidence": [
                    "type": "number",
                    "description": "0 to 1. Probability a human would accept this breakdown unchanged."
                ],
                "notes": [
                    "type": ["string", "null"],
                    "description": "Ambiguities worth a human glance. Null if none."
                ]
            ]
        ]
    }
}
