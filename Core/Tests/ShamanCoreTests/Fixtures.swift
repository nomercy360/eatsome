import Foundation
@testable import ShamanCore

/// Construction helpers for v21 meals.
///
/// Every stored food now carries composition, which is right for the app and
/// noisy in a test that cares about something else entirely. These supply a
/// plausible figure so a test about the event log is about the event log.
enum Fixture {
    /// Roughly cooked white rice, and deliberately unremarkable: a test that
    /// depends on the exact numbers should state them itself.
    static let composition = Nutrients(
        protein: 2.7, fat: 0.3, carbohydrate: 28.2, kcal: 130, sodium: 1
    )

    static func item(
        _ label: String,
        grams: Double = 100,
        per100g: Nutrients = composition,
        provenance: NutrientProvenance = .model,
        preparation: [PreparationMethod] = [],
        alternatives: [FoodAlternative] = []
    ) -> MealItem {
        MealItem(
            label: label,
            grams: grams,
            per100g: per100g,
            provenance: provenance,
            preparation: preparation,
            alternatives: alternatives
        )
    }

    static func dish(_ name: String?, count: Int = 1, panel: NutritionPanel? = nil, _ items: [MealItem]) -> MealDish {
        MealDish(name: name, count: count, panel: panel, items: items)
    }

    static func meal(
        at eatenAt: EpochMillis = 1_700_000_000_000,
        _ dishes: [MealDish],
        source: MealSource = .photo,
        share: MealShare? = nil
    ) -> MealEntry {
        MealEntry(eatenAt: eatenAt, dishes: dishes, source: source, share: share)
    }
}
