import Foundation

/// A correction to an existing classification, expressed as a delta.
///
/// The obvious implementation — send the note back with the photo and take the
/// new answer — is a regression: by the time you type "fried in butter" you have
/// already fixed portions and groups by hand, and a full re-run throws that
/// work away. So the model is asked for the smallest change that makes the list
/// right, and everything it does not mention survives untouched.
public struct MealRevision: Codable, Sendable, Hashable {
    public struct Addition: Codable, Sendable, Hashable {
        public let group: FoodGroup
        public let portion: Portion
        public let label: String?
        public let alternatives: [FoodGroup]

        public init(group: FoodGroup, portion: Portion, label: String?, alternatives: [FoodGroup] = []) {
            self.group = group
            self.portion = portion
            self.label = label
            self.alternatives = alternatives
        }
    }

    public struct Change: Codable, Sendable, Hashable {
        /// 1-based, matching the numbered list the model was shown.
        public let index: Int
        public let group: FoodGroup
        public let portion: Portion

        public init(index: Int, group: FoodGroup, portion: Portion) {
            self.index = index
            self.group = group
            self.portion = portion
        }
    }

    public let add: [Addition]
    public let revise: [Change]
    /// 1-based indices of items that are not food the person ate.
    public let remove: [Int]
    public let notes: String?

    public init(add: [Addition] = [], revise: [Change] = [], remove: [Int] = [], notes: String? = nil) {
        self.add = add
        self.revise = revise
        self.remove = remove
        self.notes = notes
    }

    public var isEmpty: Bool { add.isEmpty && revise.isEmpty && remove.isEmpty }

    /// Every index is bounds-checked and out-of-range ones are dropped. A model
    /// that miscounts must cost you nothing worse than a change that did not
    /// happen — never someone else's row edited by accident.
    public func applied(to items: [MealItem]) -> [MealItem] {
        var result = items
        for change in revise {
            let index = change.index - 1
            guard result.indices.contains(index) else { continue }
            if result[index].group != change.group { result[index].modelAlternatives = nil }
            result[index].group = change.group
            result[index].portion = change.portion
        }

        let removals = Set(remove.map { $0 - 1 }.filter { result.indices.contains($0) })
        result = result.enumerated().filter { !removals.contains($0.offset) }.map(\.element)

        result += add.map {
            MealItem(group: $0.group, portion: $0.portion, label: $0.label, modelAlternatives: $0.alternatives)
        }
        return result
    }

    /// Counts for the confirmation line, so a correction is never silent.
    public var summary: String {
        var parts: [String] = []
        if !add.isEmpty { parts.append("\(add.count) added") }
        if !revise.isEmpty { parts.append("\(revise.count) changed") }
        if !remove.isEmpty { parts.append("\(remove.count) removed") }
        return parts.isEmpty ? "Nothing to change" : parts.joined(separator: ", ")
    }
}

/// Recognizers that can also correct their own output. Kept separate from
/// `MealRecognizer` so a plain recognizer — a stub, a cache, a future on-device
/// model — is not forced to implement it.
public protocol MealRefiner: Sendable {
    func refine(
        imageData: Data?,
        mimeType: String,
        current: [MealItem],
        note: String
    ) async throws -> MealRevision
}

public enum MealRevisionPrompt {
    public static let system = """
    You are correcting an existing classification of a meal, not redoing it.

    The person has told you what is wrong or missing in their own words. Their \
    words are ground truth about the food: they were there and you were not.

    Rules:
    - Change as little as possible. Everything you do not mention is kept exactly \
      as it is. The groups and portions already in the list may have been set by \
      hand, and overwriting them destroys the person's own corrections.
    - `add` is for food that is present but missing from the list — above all the \
      ingredients no photograph can show: the fat a dish was fried in, eggs and \
      milk in a batter, sugar in a sauce, the dressing on a salad.
    - `revise` is for an item whose group or portion is wrong. Give its number \
      from the list and the corrected group and portion.
    - `remove` is for an item that is not food this person ate.
    - Report GROUPS and coarse PORTIONS only. Never calories, grams, or \
      macronutrients.
    - Portion is relative to a normal serving of that group for one adult: small \
      is about half, medium is one, large is two or more.
    - Avocado, olives, seeds, and tahini are `healthy_fats`, never fruit or \
      vegetables. Mayonnaise and cream-based dressings are `butter`; oil-based \
      dressings are `olive_oil`. `pastry` is commercially produced baked goods \
      only — food cooked at home is never `pastry`.
    - If the person's words change nothing, return empty lists.
    """

    public static func message(current: [MealItem], note: String) -> String {
        let list = current.enumerated().map { index, item in
            let name = item.label.map { "\($0) — " } ?? ""
            return "\(index + 1). \(name)\(item.group.rawValue), \(item.portion.rawValue)"
        }.joined(separator: "\n")

        return """
        Current items:
        \(list.isEmpty ? "(none)" : list)

        The person says:
        \"\"\"
        \(note)
        \"\"\"

        Return only what to add, revise, or remove. Keep everything else.
        """
    }

    /// Strict JSON Schema, OpenAI flavour.
    public static var jsonSchema: [String: Any] {
        [
            "type": "object",
            "additionalProperties": false,
            "required": ["add", "revise", "remove", "notes"],
            "properties": [
                "add": [
                    "type": "array",
                    "description": "Food that is present but missing from the list.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["group", "portion", "label", "alternatives"],
                        "properties": [
                            "group": ["type": "string", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "portion": ["type": "string", "enum": Portion.allCases.map(\.rawValue)],
                            "label": ["type": ["string", "null"], "description": "Short human name for one food."],
                            "alternatives": [
                                "type": "array",
                                "description": "Other groups this could plausibly be. Empty when obvious.",
                                "items": ["type": "string", "enum": FoodGroup.allCases.map(\.rawValue)]
                            ]
                        ]
                    ]
                ],
                "revise": [
                    "type": "array",
                    "description": "Items whose group or portion is wrong.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["index", "group", "portion"],
                        "properties": [
                            "index": ["type": "integer", "description": "The item's number in the list above, starting at 1."],
                            "group": ["type": "string", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "portion": ["type": "string", "enum": Portion.allCases.map(\.rawValue)]
                        ]
                    ]
                ],
                "remove": [
                    "type": "array",
                    "description": "Numbers of items that are not food this person ate.",
                    "items": ["type": "integer"]
                ],
                "notes": ["type": ["string", "null"], "description": "Anything worth a human glance. Null if none."]
            ]
        ]
    }

    /// The same contract in Gemini's OpenAPI subset.
    public static var geminiResponseSchema: [String: Any] {
        [
            "type": "OBJECT",
            "propertyOrdering": ["add", "revise", "remove", "notes"],
            "required": ["add", "revise", "remove", "notes"],
            "properties": [
                "add": [
                    "type": "ARRAY",
                    "description": "Food that is present but missing from the list.",
                    "items": [
                        "type": "OBJECT",
                        "propertyOrdering": ["group", "portion", "label", "alternatives"],
                        "required": ["group", "portion", "label", "alternatives"],
                        "properties": [
                            "group": ["type": "STRING", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "portion": ["type": "STRING", "enum": Portion.allCases.map(\.rawValue)],
                            "label": [
                                "type": "STRING",
                                "nullable": true,
                                "description": "Short human name for one food."
                            ],
                            "alternatives": [
                                "type": "ARRAY",
                                "description": "Other groups this could plausibly be. Empty when obvious.",
                                "items": ["type": "STRING", "enum": FoodGroup.allCases.map(\.rawValue)]
                            ]
                        ]
                    ]
                ],
                "revise": [
                    "type": "ARRAY",
                    "description": "Items whose group or portion is wrong.",
                    "items": [
                        "type": "OBJECT",
                        "propertyOrdering": ["index", "group", "portion"],
                        "required": ["index", "group", "portion"],
                        "properties": [
                            "index": ["type": "INTEGER", "description": "The item's number in the list above, starting at 1."],
                            "group": ["type": "STRING", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "portion": ["type": "STRING", "enum": Portion.allCases.map(\.rawValue)]
                        ]
                    ]
                ],
                "remove": [
                    "type": "ARRAY",
                    "description": "Numbers of items that are not food this person ate.",
                    "items": ["type": "INTEGER"]
                ],
                "notes": [
                    "type": "STRING",
                    "nullable": true,
                    "description": "Anything worth a human glance. Null if none."
                ]
            ]
        ]
    }
}
