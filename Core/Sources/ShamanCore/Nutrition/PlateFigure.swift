/// The one figure shown above a plate.
///
/// Protein is what this app counts, and on food it is always the right answer.
/// On a drink it is often zero, and "0 g protein" above a can of Monster is a
/// true sentence that tells a person nothing they did not know. When the label
/// printed caffeine, that is the fact worth reading, so it takes the slot.
///
/// This is a display decision and lives here rather than in the three views that
/// show it, because the last two bugs in this figure were both a screen deciding
/// for itself how to arrive at a number.
///
/// Caffeine is shown, never totalled — no daily figure, no target. It is the one
/// figure recognition still does not answer for: brewed coffee carries no label,
/// and nothing else supplies it, so a caffeine total would be built from the
/// packaged fraction of what a person drank while looking exactly like a total.
/// The other five escaped that objection in v21 by arriving with every food;
/// caffeine has not, and until it does it stays a fact on one card.
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
    /// `count` multiplies here where it multiplies nothing else, because a
    /// printed figure is for one container and two cans is two labels. The
    /// ingredient weights already cover every serving; a panel does not.
    public static func caffeineMilligrams(in dish: MealDish) -> Double {
        (dish.panel?.caffeine ?? 0) * Double(dish.count)
    }

    /// The figure for a plate of dishes, and the share of it that was eaten.
    ///
    /// Caffeine only steps in when every dish on the plate carries a label. A
    /// Monster next to an unlabelled espresso would otherwise report the can's
    /// 142 mg as the figure for a plate holding considerably more, and an
    /// understated caffeine number is worse than an uninformative protein one.
    public static func forPlate(_ dishes: [MealDish], share: MealShare = .whole) -> PlateFigure {
        let grams = dishes.reduce(0.0) { $0 + $1.nutrients.protein } * share.factor
        guard grams == 0, !dishes.isEmpty, dishes.allSatisfy({ $0.panel != nil }) else {
            return .protein(grams: grams)
        }
        let milligrams = dishes.reduce(0.0) { $0 + caffeineMilligrams(in: $1) } * share.factor
        return milligrams > 0 ? .caffeine(milligrams: milligrams) : .protein(grams: grams)
    }

    public static func forMeal(_ meal: MealEntry) -> PlateFigure {
        forPlate(meal.dishes, share: meal.eaten)
    }
}
