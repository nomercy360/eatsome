import Foundation

/// Protein, fat, carbohydrate, energy and sodium per 100 g for a named food,
/// from a published composition table.
///
/// The group table cannot be right for rice and pasta and bread at once — one
/// `refined_grains` row is 2.0 g of protein per 100 g, which is a rice number,
/// and against two labelled meals it read a mentaiko pasta 42% low and a
/// sauced-meat bowl 23% high. The weights were right both times.
///
/// So a food-level lookup sits in front of the group table, and the group table
/// stays exactly where it is behind it. Every row here came out of USDA SR
/// Legacy or the MEXT standard tables and carries the row it came from; see
/// `scripts/build-food-table.py`, which cannot emit a number it did not find in
/// a source file.
///
/// The four non-protein figures ride along at no extra cost: they are columns of
/// the same source row, so a lookup that can say how much protein is in 180 g of
/// salmon can say how much energy is in it without asking anything further, and
/// without asking a model to estimate anything it cannot see.
public struct FoodNutrientTable: Codable, Sendable, Equatable {
    public struct Food: Codable, Sendable, Equatable {
        /// Per 100 g of edible food.
        public let per100g: Nutrients
        /// `source:rowId`, so a figure that looks wrong can be argued with the
        /// institution that published it rather than with this file.
        public let source: String
        /// `analysed` or `estimated`. MEXT parenthesises figures it derived
        /// from a similar food rather than measured; those are published and
        /// usable, and the distinction is kept for the same reason the golden
        /// set keeps `weight_source`.
        public let basis: String
        /// The source's own name for the row, which is the only way to see that
        /// "chicken" resolved to roast bird with skin and not to a breast.
        public let name: String

        public init(per100g: Nutrients, source: String, basis: String, name: String) {
            self.per100g = per100g
            self.source = source
            self.basis = basis
            self.name = name
        }
    }

    public let version: String
    /// One representative row per food group, keyed by `FoodGroup.rawValue`.
    ///
    /// What a label lands on when the food table has never heard of it. Protein
    /// could do without this, because a miss falls through to
    /// `Protein.defaultGramsPerServing` and that covers every group; energy
    /// cannot, and a miss reading zero would build a daily figure out of the
    /// fraction of the plate that happened to resolve.
    ///
    /// `other` is deliberately absent, and stays absent. It is the bucket for
    /// food the model did not recognise, so any figure filed under it is
    /// invented rather than estimated — the argument that put 0 in the protein
    /// table after a black coffee came to be worth 2 g. Unrecognised food
    /// contributes nothing and is counted in `NutrientTotal.unresolvedGrams`.
    public let groups: [String: Food]
    public let foods: [String: Food]

    public init(version: String, groups: [String: Food] = [:], foods: [String: Food]) {
        self.version = version
        self.groups = groups
        self.foods = foods
    }

    /// The key is `group|label`, and the group half is a guard rather than a
    /// lookup: a row is only used when the model's own food group agrees with
    /// the one the table was curated under. Without it "cream" filed as `dairy`
    /// would pick up the `butter` row, which is the silent mismatch that makes
    /// fuzzy matching unusable here.
    public func food(for label: String, group: FoodGroup) -> Food? {
        for candidate in FoodLabel.candidates(for: label) {
            for name in group.storedNames {
                if let hit = foods["\(name)|\(candidate)"] { return hit }
            }
        }
        return nil
    }

    /// The stand-in for a food group, or nil for a group with no honest answer.
    public func representative(of group: FoodGroup) -> Food? { group.value(in: groups) }

    /// Everything known about a weighed, labelled item, or nil when the food is
    /// not in the table — nil means "ask the group", never zero. A miss has to
    /// cost exactly what it cost before this file existed.
    public func nutrients(in item: MealItem) -> Nutrients? {
        guard let grams = item.grams, let label = item.label else { return nil }
        guard let food = food(for: label, group: item.group) else { return nil }
        return food.per100g.forGrams(grams)
    }

    /// Grams of protein in a weighed item, kept as its own name because protein
    /// is the figure with the longest history and the only one with an eval
    /// baseline going back before this table carried anything else.
    public func grams(in item: MealItem) -> Double? { nutrients(in: item)?.protein }
}

/// Turning a model's free text into a lookup key.
///
/// Every step is an exact match against the table. Nothing here scores string
/// similarity: "chicken liver" is three times "chicken" in protein, and a fuzzy
/// hit would be wrong in silence, where a miss is wrong in a way the group
/// table already handles.
public enum FoodLabel {
    /// Lower case, punctuation to spaces, whitespace collapsed. Must agree with
    /// `normalise` in `scripts/build-food-table.py`, or the client misses rows
    /// the build believes it published.
    public static func normalised(_ label: String) -> String {
        let mapped = label.map { character -> Character in
            character.isLetter || character.isNumber || character.isWhitespace ? character : " "
        }
        return String(mapped).lowercased().split(separator: " ").joined(separator: " ")
    }

    /// The attempts, in order, each of them exact.
    ///
    /// Only two rewrites, and both drop text the model added rather than
    /// changing the food it names. Adjectives are never stripped: "fried
    /// chicken" and "chicken" are different foods and the table has both.
    public static func candidates(for label: String) -> [String] {
        var attempts: [String] = []
        func add(_ value: String) {
            guard !value.isEmpty, !attempts.contains(value) else { return }
            attempts.append(value)
        }

        add(normalised(label))
        // "mentaiko (pollock roe)" is one food with a gloss attached.
        if let paren = label.firstIndex(of: "(") {
            add(normalised(String(label[label.startIndex..<paren])))
        }
        // A plural the table happens to hold in the singular, and only the
        // trivial case — no stemming, which would collapse "olives" onto "olive
        // oil" given half a chance.
        if let last = attempts.first, last.hasSuffix("s") {
            add(String(last.dropLast()))
        }
        return attempts
    }
}
