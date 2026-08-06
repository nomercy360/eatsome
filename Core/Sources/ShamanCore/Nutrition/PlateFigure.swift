/// The one figure shown above a plate.
///
/// Protein is what this app counts, and on food it is always the right answer.
/// On a drink it is often zero, and "0 g protein" above a can of Monster is a
/// true sentence that tells a person nothing they did not know. When the label
/// printed caffeine, that is the fact worth reading, so it takes the slot.
///
/// This is a display decision and lives here rather than in the three views
/// that show it, because the last two bugs in this figure were both a screen
/// deciding for itself how to arrive at a number.
///
/// Caffeine is shown, never totalled — no daily figure, no target. Brewed
/// coffee carries no label, so a caffeine total would be built from the
/// packaged fraction of what a person drank while looking exactly like a
/// total. That is the same reason `NutritionPanel.calories` is never summed.
public enum PlateFigure: Equatable, Sendable {
    case protein(grams: Double)
    case caffeine(milligrams: Double)

    /// What to write next to the sentence.
    public var text: String {
        switch self {
        case .protein(let grams): "\(Int(grams.rounded())) g protein"
        case .caffeine(let milligrams): "\(Int(milligrams.rounded())) mg caffeine"
        }
    }

    /// Milligrams of caffeine in one dish, from the label and only the label.
    ///
    /// `size` drops out exactly as it does for protein: a printed figure is for
    /// what the container holds, and "large" says nothing about a 355 ml can.
    public static func caffeineMilligrams(in dish: MealDish) -> Double {
        (dish.panel?.caffeine ?? 0) * Double(dish.count)
    }

    /// The figure for a plate of dishes, and the share of it that was eaten.
    ///
    /// Caffeine only steps in when every dish on the plate carries a label.
    /// A Monster next to an unlabelled espresso would otherwise report the
    /// can's 142 mg as the figure for a plate holding considerably more, and an
    /// understated caffeine number is worse than an uninformative protein one.
    public static func forPlate(
        _ dishes: [MealDish],
        share: MealShare = .whole,
        gramsPerServing: [String: Double] = Protein.defaultGramsPerServing
    ) -> PlateFigure {
        let grams = Protein.grams(in: dishes, gramsPerServing: gramsPerServing) * share.factor
        guard grams == 0, !dishes.isEmpty, dishes.allSatisfy({ $0.panel != nil }) else {
            return .protein(grams: grams)
        }
        let milligrams = dishes.reduce(0.0) { $0 + caffeineMilligrams(in: $1) } * share.factor
        return milligrams > 0 ? .caffeine(milligrams: milligrams) : .protein(grams: grams)
    }

    /// The figure for a saved meal. A meal from before dishes has no panels to
    /// read and is always its protein.
    public static func forMeal(
        _ meal: MealEntry,
        gramsPerServing: [String: Double] = Protein.defaultGramsPerServing
    ) -> PlateFigure {
        guard let dishes = meal.storedDishes else {
            return .protein(grams: Protein.grams(in: meal, gramsPerServing: gramsPerServing))
        }
        return forPlate(dishes, share: meal.eaten, gramsPerServing: gramsPerServing)
    }
}
