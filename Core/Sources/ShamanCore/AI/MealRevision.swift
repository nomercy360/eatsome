import Foundation

/// A correction to an existing classification, expressed as a delta.
///
/// The obvious implementation — send the note back with the photo and take the
/// new answer — is a regression: by the time you type "fried in butter" you have
/// already fixed weights and names by hand, and a full re-run throws that work
/// away. So the model is asked for the smallest change that makes the list
/// right, and everything it does not mention survives untouched.
///
/// From v21 a change must restate the composition as well as the weight. Stored
/// figures and editable rows can desync, and a revision that moved a food from
/// "chicken" to "fried chicken" while leaving the old numbers behind would be a
/// meal whose figures quietly stopped describing its own contents.
public struct MealRevision: Codable, Sendable, Hashable {
    public struct Addition: Codable, Sendable, Hashable {
        public let label: String
        /// Edible weight of everything of this ingredient the person ate.
        public let grams: Double
        public let per100g: Nutrients
        public let preparation: [PreparationMethod]
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

    public struct Change: Codable, Sendable, Hashable {
        /// 1-based, matching the numbered list the model was shown.
        public let index: Int
        public let label: String
        /// The corrected weight, repeated unchanged when only the name was
        /// wrong. A revision used to carry a `Portion` here, which could not move
        /// a weighed item at all: the delta applied cleanly and changed nothing
        /// anyone could see.
        public let grams: Double
        /// The composition of the food as it now stands. Required for the reason
        /// in the type comment — a renamed food with the old numbers is worse
        /// than an uncorrected one, because it looks corrected.
        public let per100g: Nutrients
        public let preparation: [PreparationMethod]

        public init(
            index: Int,
            label: String,
            grams: Double,
            per100g: Nutrients,
            preparation: [PreparationMethod] = []
        ) {
            self.index = index
            self.label = label
            self.grams = grams
            self.per100g = per100g
            self.preparation = preparation
        }

        private enum CodingKeys: String, CodingKey {
            case index, label, grams, preparation
            case per100g = "per_100g"
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
    ///
    /// A corrected row is marked `user`: the person is why it changed, even
    /// though a model wrote the figures, and treating it as ordinary model
    /// output would let a later re-price silently undo the correction.
    public func applied(to items: [MealItem]) -> [MealItem] {
        var result = items
        for change in revise {
            let index = change.index - 1
            guard result.indices.contains(index) else { continue }
            // The shortlist answered a question the person has now answered
            // differently.
            if result[index].label != change.label { result[index].alternatives = [] }
            result[index].label = change.label
            result[index].grams = change.grams
            result[index].per100g = change.per100g
            result[index].preparation = change.preparation
            result[index].provenance = .all(.user)
            result[index].sourceRef = nil
        }

        let removals = Set(remove.map { $0 - 1 }.filter { result.indices.contains($0) })
        result = result.enumerated().filter { !removals.contains($0.offset) }.map(\.element)

        result += add.map {
            MealItem(
                label: $0.label,
                grams: $0.grams,
                per100g: $0.per100g,
                provenance: .all(.user),
                preparation: $0.preparation,
                alternatives: $0.alternatives
            )
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
    // `system` is generated from `prompts/revision-v3.md` into
    // MealRevisionPrompt+Generated.swift. It was a string literal here and a
    // second string literal in `Backend/worker/ai/revision.ts`, and the two had
    // drifted apart in three rules while both claimed to be the same
    // instructions — the same failure the recognition prompt was generated to
    // stop. Edit the file and re-run `node scripts/sync-prompt.mjs`.

    public static func message(current: [MealItem], note: String) -> String {
        let list = current.enumerated().map { index, item in
            "\(index + 1). \(item.label), \(Int(item.grams.rounded())) g"
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
        let preparation: [String: Any] = [
            "type": "array",
            "items": ["type": "string", "enum": PreparationMethod.allCases.map(\.rawValue)]
        ]
        let composition: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
            "description": "Composition per 100 g of the food as it now stands, as prepared.",
            "properties": [
                "protein": ["type": "number"], "fat": ["type": "number"],
                "carbohydrate": ["type": "number"], "kcal": ["type": "number"],
                "sodium_mg": ["type": "number"]
            ]
        ]
        let alternative: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["label", "per_100g"],
            "properties": ["label": ["type": "string"], "per_100g": composition]
        ]
        return [
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
                        "required": ["label", "grams", "per_100g", "preparation", "alternatives"],
                        "properties": [
                            "label": ["type": "string", "description": "Short human name for one food."],
                            "grams": ["type": "number", "description": "\(MealPrompt.gramsDescription)"],
                            "per_100g": composition,
                            "preparation": preparation,
                            "alternatives": [
                                "type": "array",
                                "description": "Other foods this could plausibly be, each priced. Empty when obvious.",
                                "items": alternative
                            ]
                        ]
                    ]
                ],
                "revise": [
                    "type": "array",
                    "description": "Items whose identity, preparation, or weight is wrong.",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["index", "label", "grams", "per_100g", "preparation"],
                        "properties": [
                            "index": ["type": "integer", "description": "The item's number in the list above, starting at 1."],
                            "label": ["type": "string", "description": "The food as it now stands, corrected or repeated."],
                            "grams": ["type": "number", "description": "\(MealPrompt.gramsDescription)"],
                            "per_100g": composition,
                            "preparation": preparation
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
        let preparation: [String: Any] = [
            "type": "ARRAY",
            "items": ["type": "STRING", "enum": PreparationMethod.allCases.map(\.rawValue)]
        ]
        let composition: [String: Any] = [
            "type": "OBJECT",
            "description": "Composition per 100 g of the food as it now stands, as prepared.",
            "propertyOrdering": ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
            "required": ["protein", "fat", "carbohydrate", "kcal", "sodium_mg"],
            "properties": [
                "protein": ["type": "NUMBER"], "fat": ["type": "NUMBER"],
                "carbohydrate": ["type": "NUMBER"], "kcal": ["type": "NUMBER"],
                "sodium_mg": ["type": "NUMBER"]
            ]
        ]
        let alternative: [String: Any] = [
            "type": "OBJECT",
            "propertyOrdering": ["label", "per_100g"],
            "required": ["label", "per_100g"],
            "properties": ["label": ["type": "STRING"], "per_100g": composition]
        ]
        return [
            "type": "OBJECT",
            "propertyOrdering": ["add", "revise", "remove", "notes"],
            "required": ["add", "revise", "remove", "notes"],
            "properties": [
                "add": [
                    "type": "ARRAY",
                    "description": "Food that is present but missing from the list.",
                    "items": [
                        "type": "OBJECT",
                        "propertyOrdering": ["label", "grams", "per_100g", "preparation", "alternatives"],
                        "required": ["label", "grams", "per_100g", "preparation", "alternatives"],
                        "properties": [
                            "label": ["type": "STRING", "description": "Short human name for one food."],
                            "grams": ["type": "NUMBER", "description": "\(MealPrompt.gramsDescription)"],
                            "per_100g": composition,
                            "preparation": preparation,
                            "alternatives": [
                                "type": "ARRAY",
                                "description": "Other foods this could plausibly be, each priced. Empty when obvious.",
                                "items": alternative
                            ]
                        ]
                    ]
                ],
                "revise": [
                    "type": "ARRAY",
                    "description": "Items whose identity, preparation, or weight is wrong.",
                    "items": [
                        "type": "OBJECT",
                        "propertyOrdering": ["index", "label", "grams", "per_100g", "preparation"],
                        "required": ["index", "label", "grams", "per_100g", "preparation"],
                        "properties": [
                            "index": ["type": "INTEGER", "description": "The item's number in the list above, starting at 1."],
                            "label": ["type": "STRING", "description": "The food as it now stands, corrected or repeated."],
                            "grams": ["type": "NUMBER", "description": "\(MealPrompt.gramsDescription)"],
                            "per_100g": composition,
                            "preparation": preparation
                        ]
                    ]
                ],
                "remove": [
                    "type": "ARRAY",
                    "description": "Numbers of items that are not food this person ate.",
                    "items": ["type": "INTEGER"]
                ],
                "notes": ["type": "STRING", "nullable": true, "description": "Anything worth a human glance. Null if none."]
            ]
        ]
    }
}
