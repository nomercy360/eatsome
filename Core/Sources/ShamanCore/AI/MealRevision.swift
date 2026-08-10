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
        /// Edible weight of everything of this ingredient the person ate.
        public let grams: Double
        public let label: String?
        public let alternatives: [FoodGroup]

        public init(group: FoodGroup, grams: Double, label: String?, alternatives: [FoodGroup] = []) {
            self.group = group
            self.grams = grams
            self.label = label
            self.alternatives = alternatives
        }
    }

    public struct Change: Codable, Sendable, Hashable {
        /// 1-based, matching the numbered list the model was shown.
        public let index: Int
        public let group: FoodGroup
        /// The corrected weight, repeated unchanged when only the group was
        /// wrong. A revision used to carry a `Portion` here, which could not move
        /// a weighed item at all — `effectiveServings` prefers grams, so the
        /// delta applied cleanly and changed nothing anyone could see.
        public let grams: Double

        public init(index: Int, group: FoodGroup, grams: Double) {
            self.index = index
            self.group = group
            self.grams = grams
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
            result[index].grams = change.grams
            // A row flattened before grams carries the ladder's arithmetic in
            // `servings`, and that would outrank nothing but still sit there
            // contradicting the weight just written. Clearing it leaves one
            // quantity on the item, which is the whole point.
            result[index].servings = nil
        }

        let removals = Set(remove.map { $0 - 1 }.filter { result.indices.contains($0) })
        result = result.enumerated().filter { !removals.contains($0.offset) }.map(\.element)

        result += add.map {
            MealItem(group: $0.group, label: $0.label, modelAlternatives: $0.alternatives, grams: $0.grams)
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
    // `system` is generated from `prompts/revision-v2.md` into
    // MealRevisionPrompt+Generated.swift. It was a string literal here and a
    // second string literal in `Backend/worker/ai/revision.ts`, and the two had
    // drifted apart in three rules while both claimed to be the same
    // instructions — the same failure the recognition prompt was generated to
    // stop. Edit the file and re-run `node scripts/sync-prompt.mjs`.

    public static func message(current: [MealItem], note: String) -> String {
        let list = current.enumerated().map { index, item in
            let name = item.label.map { "\($0) — " } ?? ""
            let weight = item.grams.map { "\(Int($0.rounded())) g" } ?? "no weight recorded"
            return "\(index + 1). \(name)\(item.group.rawValue), \(weight)"
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
                        "required": ["group", "grams", "label", "alternatives"],
                        "properties": [
                            "group": ["type": "string", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "grams": ["type": "number", "description": "\(MealPrompt.gramsDescription)"],
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
                    "description": "Items whose group or weight is wrong.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["index", "group", "grams"],
                        "properties": [
                            "index": ["type": "integer", "description": "The item's number in the list above, starting at 1."],
                            "group": ["type": "string", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "grams": ["type": "number", "description": "\(MealPrompt.gramsDescription)"]
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
                        "propertyOrdering": ["group", "grams", "label", "alternatives"],
                        "required": ["group", "grams", "label", "alternatives"],
                        "properties": [
                            "group": ["type": "STRING", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "grams": ["type": "NUMBER", "description": "\(MealPrompt.gramsDescription)"],
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
                    "description": "Items whose group or weight is wrong.",
                    "items": [
                        "type": "OBJECT",
                        "propertyOrdering": ["index", "group", "grams"],
                        "required": ["index", "group", "grams"],
                        "properties": [
                            "index": ["type": "INTEGER", "description": "The item's number in the list above, starting at 1."],
                            "group": ["type": "STRING", "enum": FoodGroup.allCases.map(\.rawValue)],
                            "grams": ["type": "NUMBER", "description": "\(MealPrompt.gramsDescription)"]
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
