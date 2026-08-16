import Foundation

// Corrections, as deltas.
//
// The obvious implementation — send the words back with the photo and take the
// new answer — is a regression: by the time you type "fried in butter" you have
// already fixed weights and names by hand, and a full re-run throws that work
// away. So the model is asked for the smallest change that makes the thing
// right, and everything it does not mention survives untouched.
//
// This is a wire type (`per_100g`, `dish_counts`) with an `applied(to:)` that
// produces the stored form. The rule it is held to is the one recognition is
// held to, restated: a food row that moves restates its composition.

/// A correction to a meal.
///
/// A change must restate composition as well as weight. Stored figures and
/// editable rows can desync, and a revision that moved a food from "chicken"
/// to "fried chicken" while leaving the old numbers behind would be a meal
/// whose figures quietly stopped describing its own contents — worse than an
/// uncorrected one, because it looks corrected. `per100g` is therefore
/// non-optional on `Addition` and on `Change`, as it is in the Zod contract and
/// in both provider schemas.
public struct MealRevision: Decodable, Sendable, Hashable {
    public struct Addition: Decodable, Sendable, Hashable {
        public let label: String
        /// Edible weight of everything of this ingredient the person ate.
        public let grams: Double
        public let per100g: Nutrients
        public let preparation: [PreparationMethod]
        /// Wire-shaped, like recognition's: a rival arrives priced and weighed
        /// and only becomes a `FoodAlternative` (which carries an id) when
        /// applied. Decoding the stored type here required an `id` the model
        /// never sends, so any correction that added a row with rivals failed.
        public let alternatives: [RecognizedAlternative]

        public init(
            label: String,
            grams: Double,
            per100g: Nutrients,
            preparation: [PreparationMethod] = [],
            alternatives: [RecognizedAlternative] = []
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

    public struct Change: Decodable, Sendable, Hashable {
        /// 1-based, matching the numbered list the model was shown.
        public let index: Int
        public let label: String
        /// The corrected weight, repeated unchanged when only the name was
        /// wrong.
        public let grams: Double
        /// The composition of the food as it now stands.
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

    public struct DishCountChange: Decodable, Sendable, Hashable {
        /// 1-based, matching the numbered dish list the model was shown.
        public let index: Int
        public let count: Int

        public init(index: Int, count: Int) {
            self.index = index
            self.count = count
        }
    }

    public struct DishNameChange: Decodable, Sendable, Hashable {
        public let index: Int
        public let name: String

        public init(index: Int, name: String) {
            self.index = index
            self.name = name
        }
    }

    public let add: [Addition]
    public let revise: [Change]
    public let dishCounts: [DishCountChange]
    public let dishNames: [DishNameChange]
    /// 1-based indices of items that are not food the person ate.
    public let remove: [Int]
    public let notes: String?

    public init(
        add: [Addition] = [],
        revise: [Change] = [],
        dishCounts: [DishCountChange] = [],
        dishNames: [DishNameChange] = [],
        remove: [Int] = [],
        notes: String? = nil
    ) {
        self.add = add
        self.revise = revise
        self.dishCounts = dishCounts
        self.dishNames = dishNames
        self.remove = remove
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case add, revise, remove, notes
        case dishCounts = "dish_counts"
        case dishNames = "dish_names"
    }

    public var isEmpty: Bool {
        add.isEmpty && revise.isEmpty && dishCounts.isEmpty && dishNames.isEmpty && remove.isEmpty
    }

    /// The flat item list, corrected.
    ///
    /// Every index is bounds-checked and out-of-range ones are dropped: a model
    /// that miscounts must cost you nothing worse than a change that did not
    /// happen — never someone else's row edited by accident.
    ///
    /// A corrected row is stamped `.user`: the person is why it changed, even
    /// though a model wrote the figures, and treating it as ordinary model
    /// output would let a later re-price silently undo the correction. A
    /// renamed row also loses its `alternatives` and `sizes` — the shortlist
    /// answered a question the person has now answered differently, and the
    /// sizes were the old product's.
    public func applied(to items: [MealItem]) -> [MealItem] {
        var result = items
        for change in revise {
            let index = change.index - 1
            guard result.indices.contains(index) else { continue }
            if result[index].label != change.label {
                result[index].alternatives = []
                result[index].sizes = []
            }
            result[index].label = change.label
            result[index].grams = change.grams
            result[index].per100g = change.per100g
            result[index].preparation = change.preparation
            result[index].provenance = .user
        }

        let removals = Set(remove.map { $0 - 1 }.filter { result.indices.contains($0) })
        result = result.enumerated().filter { !removals.contains($0.offset) }.map(\.element)

        result += add.map {
            MealItem(
                label: $0.label,
                preparation: $0.preparation,
                grams: $0.grams,
                per100g: $0.per100g,
                provenance: .user,
                alternatives: $0.alternatives.map(\.stored)
            )
        }
        return result
    }

    /// The dishes, corrected, without flattening away the structure a count
    /// change refers to. Every existing row returns to its dish by id; added
    /// rows land in one unnamed dish; a count change scales its dish exactly
    /// once, through `scaled(toCount:)`, so the weights are rewritten rather
    /// than multiplied at score time.
    public func applied(to dishes: [MealDish]) -> [MealDish] {
        let corrected = applied(to: dishes.flatMap(\.items))
        let byID = Dictionary(corrected.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        var placed = Set<UUID>()
        let requestedCounts = Dictionary(
            dishCounts.map { ($0.index - 1, min(24, max(1, $0.count))) },
            uniquingKeysWith: { _, latest in latest }
        )
        let requestedNames = Dictionary(
            dishNames.map { ($0.index - 1, $0.name) },
            uniquingKeysWith: { _, latest in latest }
        )

        var regrouped: [MealDish] = []
        for (index, dish) in dishes.enumerated() {
            var copy = dish
            copy.items = dish.items.compactMap { original in
                guard let updated = byID[original.id] else { return nil }
                placed.insert(original.id)
                return updated
            }
            guard !copy.items.isEmpty else { continue }
            if let name = requestedNames[index] { copy.name = name }
            if let count = requestedCounts[index] { copy = copy.scaled(toCount: count) }
            regrouped.append(copy)
        }

        let added = corrected.filter { !placed.contains($0.id) }
        if !added.isEmpty { regrouped.append(MealDish(name: nil, items: added)) }
        return regrouped
    }

    /// The meal, corrected and marked so. Nothing else on it moves.
    public func applied(to meal: MealEntry) -> MealEntry {
        var copy = meal
        copy.dishes = applied(to: meal.dishes)
        copy.wasCorrected = true
        return copy
    }

    /// Counts for the confirmation line, so a correction is never silent.
    public var summary: String {
        var parts: [String] = []
        if !add.isEmpty { parts.append("\(add.count) added") }
        if !revise.isEmpty { parts.append("\(revise.count) changed") }
        if !dishCounts.isEmpty { parts.append("\(dishCounts.count) portion count changed") }
        if !dishNames.isEmpty { parts.append("\(dishNames.count) dish renamed") }
        if !remove.isEmpty { parts.append("\(remove.count) removed") }
        return parts.isEmpty ? "Nothing to change" : parts.joined(separator: ", ")
    }
}
