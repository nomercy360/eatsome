import Foundation

/// One to five olives per meal, computed from what is already known.
///
/// Every configured food group has a direction, and a plate is the sum of those
/// directions weighted by how much of each is on it. Nothing new is measured and
/// nothing new is asked of a model.
///
/// Deliberately coarse. The data cannot tell grilled from fried, poached from
/// deep-fried, or a dressing from a drizzle, so five steps is all the precision
/// that is honest — a plate rated 3.4 out of 5 would be claiming a resolution
/// nothing in the pipeline has.
///
/// One rule is load-bearing: **one olive is a treat, never a fail.** An almond croissant is one olive and
///   the words next to it say "a treat — it happens". The app is additive; a
///   scale whose bottom end is a reprimand is not.
public struct OliveRating: Sendable, Hashable {
    /// What gets drawn: filled olives out of five.
    public let olives: Int
    /// The unrounded figure, kept so a day can be averaged from its meals
    /// without rounding each one first and accumulating the error.
    public let value: Double
    /// What actually moved it, strongest first — the groups the one-line reason
    /// is written from. Empty on a plate where nothing has a direction.
    public let leading: [FoodGroup]

    public static let range = 1...5

    /// Where a plate starts before anything on it is counted.
    ///
    /// Three, not zero: most food is neither good nor bad for this pattern, and a
    /// scale that opens at the bottom would make an ordinary lunch look like a
    /// failure to have eaten sardines.
    public static let neutral = 3.0
}

/// How much each group moves a plate, and in which direction.
///
/// Positive groups lift the plate rating; negative ones lower it. Everything unnamed is neutral and does
/// nothing at all — which is most of the table, and deliberately so: coffee,
/// eggs, rice and chicken have no business nudging a rating in either direction.
///
/// Lives in `shaman-config.json` next to the protein table so it can be retuned
/// without an app update, exactly like every other number here that is a
/// judgement rather than a fact.
public struct OliveConfiguration: Codable, Sendable, Hashable {
    /// Keyed by `FoodGroup.rawValue`, so a group this build has never heard of
    /// can still be given a weight from a remote config.
    public var weights: [String: Double]

    public init(weights: [String: Double] = OliveConfiguration.defaultWeights) {
        self.weights = weights
    }

    /// Hand-set, and the values are relative rather than measured — there is no
    /// ground truth for a plate rating, only the configured pattern's own account
    /// of itself. Fish, legumes and olive oil carry the most; whole grains carry least among the
    /// positives because refined and whole grains look identical in a photograph
    /// often enough that a confident weight would be spending confidence the
    /// recognition does not have.
    public static let defaultWeights: [String: Double] = [
        FoodGroup.fish.rawValue: 1.0,
        FoodGroup.legumes.rawValue: 1.0,
        FoodGroup.oliveOil.rawValue: 0.8,
        FoodGroup.vegetables.rawValue: 0.7,
        FoodGroup.nuts.rawValue: 0.7,
        FoodGroup.cookedTomatoSauce.rawValue: 0.5,
        FoodGroup.wholeGrains.rawValue: 0.5,
        FoodGroup.fruit.rawValue: 0.5,

        FoodGroup.processedMeat.rawValue: -1.0,
        FoodGroup.pastry.rawValue: -0.8,
        FoodGroup.redMeat.rawValue: -0.8,
        FoodGroup.sugaryDrinks.rawValue: -0.8,
        FoodGroup.sweets.rawValue: -0.7,
        FoodGroup.butter.rawValue: -0.6
    ]

    public func weight(for group: FoodGroup) -> Double {
        group.value(in: weights) ?? 0
    }
}

extension OliveRating {
    /// What one meal is worth.
    ///
    /// The quantity per group comes from `MealEntry.servings(of:)`, which is
    /// already capped at one large portion per group and scaled by how much of
    /// the plate was yours. That matters twice over here: four rows of fruit on
    /// one platter must be one plate of fruit, and a shared bowl you had a taste
    /// of must not be rated as though you ate the lot.
    public static func forMeal(
        _ meal: MealEntry,
        configuration: OliveConfiguration = OliveConfiguration(),
        servingGrams: [String: Double] = ServingWeight.defaultGrams
    ) -> OliveRating {
        var contributions: [FoodGroup: Double] = [:]
        for group in Set(meal.items.map(\.group)) {
            let weight = configuration.weight(for: group)
            guard weight != 0 else { continue }
            let servings = meal.servings(of: group, servingGrams: servingGrams)
            guard servings > 0 else { continue }
            contributions[group] = weight * servings
        }

        let value = (neutral + contributions.values.reduce(0, +))
            .clamped(to: Double(range.lowerBound)...Double(range.upperBound))

        return OliveRating(
            olives: Int(value.rounded()),
            value: value,
            leading: contributions
                .sorted { abs($0.value) == abs($1.value)
                    ? $0.key.rawValue < $1.key.rawValue
                    : abs($0.value) > abs($1.value) }
                .map(\.key)
        )
    }

    /// The day as its meals, weighted by how big each one was.
    ///
    /// A portion-weighted average rather than a plain one, because a plain
    /// average lets a black coffee count as much as dinner: two neutral drinks
    /// either side of a four-olive meal would drag the day back to three. Weight
    /// is total servings on the plate, floored so a genuinely tiny meal still
    /// registers as having happened.
    ///
    /// Nil for a day with nothing logged — an unrated day and a three-olive day
    /// are different facts, and a screen that draws them the same way is telling
    /// someone they ate averagely on a day they did not eat.
    public static func forDay(
        _ meals: [MealEntry],
        configuration: OliveConfiguration = OliveConfiguration(),
        servingGrams: [String: Double] = ServingWeight.defaultGrams
    ) -> OliveRating? {
        guard !meals.isEmpty else { return nil }

        var total = 0.0
        var weightTotal = 0.0
        var contributions: [FoodGroup: Double] = [:]

        for meal in meals {
            let rating = forMeal(meal, configuration: configuration, servingGrams: servingGrams)
            let weight = max(0.25, meal.totalServings(servingGrams: servingGrams))
            total += rating.value * weight
            weightTotal += weight
            for group in rating.leading {
                contributions[group, default: 0] +=
                    configuration.weight(for: group)
                    * meal.servings(of: group, servingGrams: servingGrams)
            }
        }

        guard weightTotal > 0 else { return nil }
        let value = (total / weightTotal)
            .clamped(to: Double(range.lowerBound)...Double(range.upperBound))

        return OliveRating(
            olives: Int(value.rounded()),
            value: value,
            leading: contributions
                .sorted { abs($0.value) == abs($1.value)
                    ? $0.key.rawValue < $1.key.rawValue
                    : abs($0.value) > abs($1.value) }
                .map(\.key)
        )
    }
}

// MARK: - Saying it out loud

extension OliveRating {
    /// "Four olives". Spelled, because this is a headline and a digit in a
    /// headline reads as a measurement — which is the one thing a rating this
    /// coarse must not look like.
    ///
    /// Its own five words rather than the app's general number speller: that one
    /// lives in the UI layer, and a rating that only ever says one to five does
    /// not need a dependency to say it.
    public var spelled: String {
        let words = ["", "One", "Two", "Three", "Four", "Five"]
        guard Self.range.contains(olives) else { return "\(olives) olives" }
        return "\(words[olives]) olive\(olives == 1 ? "" : "s")"
    }

    /// The one line under the olives saying why.
    ///
    /// It names the food, never the arithmetic: "Fish, beans, greens and olive
    /// oil" is something a person can check against their own plate, where
    /// "+2.4 from three positive groups" is something they can only take on
    /// trust. Anyone who wants the arithmetic can open it; nobody has to.
    public func reason(configuration: OliveConfiguration = OliveConfiguration()) -> String {
        let positives = leading.filter { configuration.weight(for: $0) > 0 }
        let negatives = leading.filter { configuration.weight(for: $0) < 0 }

        switch olives {
        case 5:
            return "\(named(positives)) — about as strong as a plate gets."
        case 4:
            return positives.isEmpty
                ? "A good plate."
                : "\(named(positives)) — a good plate."
        case 3 where positives.isEmpty && negatives.isEmpty:
            return "This meal sits in the middle."
        case 3:
            return negatives.isEmpty
                ? "\(named(positives)) — a fair plate."
                : "\(named(positives.isEmpty ? negatives : positives)) — it evens out."
        case 2:
            return negatives.isEmpty
                ? "Not much here for the pattern."
                : "\(named(negatives)) — fine now and then."
        default:
            // One olive is the only rating with fixed words. Every other line
            // describes the food; this one refuses to describe it, because the
            // sentence a person expects here is a telling-off and the point is
            // that they are not going to get one.
            return "A treat — it happens."
        }
    }

    /// Up to three groups, in the vocabulary a chip uses, joined as a person
    /// would say them. More than three and the line stops being a sentence and
    /// starts being the list the sentence was meant to replace.
    private func named(_ groups: [FoodGroup]) -> String {
        let names = groups.prefix(3).map(\.shortName)
        switch names.count {
        case 0: return "This plate"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

extension MealEntry {
    /// Everything on the plate, in servings, after the per-group cap and the
    /// share. The size of a meal rather than its quality — which is what the
    /// day's average needs to weight by.
    public func totalServings(
        servingGrams: [String: Double] = ServingWeight.defaultGrams
    ) -> Double {
        Set(items.map(\.group))
            .reduce(0) { $0 + servings(of: $1, servingGrams: servingGrams) }
    }
}

private extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
