import Foundation

/// Nutrition figures transcribed from packaging, for one serving as the label
/// defines it.
///
/// Read, never estimated — that distinction is the entire justification for
/// this type. A model asked for grams from pixels returns a figure with 30–50%
/// error that is indistinguishable from data, which is why nothing here ever
/// asks for one. A model reading a printed panel is doing OCR on a fact, and a
/// fact is worth keeping.
///
/// Every field is optional because an unreadable figure has to come back
/// absent. A fabricated number stored in the one place reserved for confirmed
/// values is worse than no number, since being trustworthy is the field's only
/// purpose.
public struct NutritionPanel: Codable, Sendable, Hashable {
    /// Grams, for one serving as printed.
    public var protein: Double?
    /// Kept because it was printed, never summed and never shown as a daily
    /// figure. Only packaged food carries a label, so a total built from these
    /// would be computed from the packaged fraction of a diet while looking
    /// exactly like a total — worse than absent. See `Protein` for the one
    /// number that does have a complete baseline and therefore can be totalled.
    public var calories: Double?
    public var fat: Double?
    public var carbohydrate: Double?
    /// Grams of salt equivalent, as Japanese labels print it. `sodium` is
    /// derived from it by the backend when only salt was printed.
    public var salt: Double?
    public var sodium: Double?
    /// Milligrams.
    public var caffeine: Double?
    /// What the figures were counted against on the label, retained as
    /// provenance. The backend has already scaled them to one container, so
    /// this reads `per_container` on anything usable — but a panel it could not
    /// scale keeps the basis it was printed with, which is what makes a wrong
    /// figure diagnosable rather than merely wrong.
    public var basis: String?
    public var netMl: Double?
    public var netG: Double?

    public init(
        protein: Double? = nil,
        calories: Double? = nil,
        fat: Double? = nil,
        carbohydrate: Double? = nil,
        salt: Double? = nil,
        sodium: Double? = nil,
        caffeine: Double? = nil,
        basis: String? = nil,
        netMl: Double? = nil,
        netG: Double? = nil
    ) {
        self.protein = protein
        self.calories = calories
        self.fat = fat
        self.carbohydrate = carbohydrate
        self.salt = salt
        self.sodium = sodium
        self.caffeine = caffeine
        self.basis = basis
        self.netMl = netMl
        self.netG = netG
    }

    private enum CodingKeys: String, CodingKey {
        case protein, calories, fat, carbohydrate, salt, sodium, caffeine, basis
        case netMl = "net_ml"
        case netG = "net_g"
    }

    public var isEmpty: Bool {
        protein == nil && calories == nil && fat == nil && carbohydrate == nil
            && salt == nil && sodium == nil && caffeine == nil
    }
}

/// One named thing on the tray, and what it is made of.
///
/// The dish is what a person recognises — "kaisen don", "two beers" — and the
/// ingredients underneath are what the diet score is made of. Quantity lives
/// here rather than on the ingredients: `count` is how many servings are
/// present and `size` is how big one of them is, while an ingredient's
/// `portion` says how much of it goes into a single serving. Three factors,
/// each answered independently, because a model applying the count itself
/// doubles the meal and nothing downstream can tell that from a large plate.
public struct MealDish: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// How many servings of this dish. Three beers is one dish with count 3.
    public var count: Int
    /// How big ONE serving is. Ignored when `panel` is present: a packaged
    /// item's serving is whatever the box holds, and "large" means nothing
    /// about a 200 ml carton.
    public var size: Portion
    /// What the packaging said, when it said anything. Nil for almost all food,
    /// which is cooked and has nothing printed on it.
    public var panel: NutritionPanel?
    /// The ingredients as recognised: each `portion` is that ingredient's share
    /// of ONE serving, never of the whole dish.
    public var items: [MealItem]

    public init(
        id: UUID = UUIDv7.generate(),
        name: String,
        count: Int = 1,
        size: Portion = .medium,
        panel: NutritionPanel? = nil,
        items: [MealItem] = []
    ) {
        self.id = id
        self.name = name
        self.count = count
        self.size = size
        self.panel = panel
        self.items = items
    }

    /// What one ingredient of this dish contributes once the dish's own
    /// quantity is applied.
    public var multiplier: Double { Double(count) * size.servings }

    /// The dish as rows the scorer can add up, each carrying the servings the
    /// three factors produced.
    ///
    /// `MealEntry` stores both this and the dishes, so that a build which has
    /// never heard of dishes still scores a meal correctly. They can only
    /// disagree if something writes one without the other, which is why this is
    /// the single way the flat list is ever produced.
    /// Rebuild dishes from a flat list that has been edited.
    ///
    /// Corrections arrive as a delta against the flat items — the refiner adds,
    /// revises and removes rows, and knows nothing about dishes. Regrouping by
    /// name puts the survivors back where they were and keeps each dish's own
    /// `count`, `size` and `panel`, which no flat row carries. Anything the
    /// correction added has no dish name and lands in one unnamed dish, because
    /// guessing which dish a new food joined would silently change a count.
    public static func regrouped(_ items: [MealItem], keeping dishes: [MealDish]) -> [MealDish] {
        var byName: [String: MealDish] = [:]
        for dish in dishes { byName[dish.name] = dish }

        var order: [String?] = []
        var grouped: [String?: [MealItem]] = [:]
        for item in items {
            if grouped[item.dish] == nil { order.append(item.dish) }
            grouped[item.dish, default: []].append(item)
        }

        return order.compactMap { name in
            guard let members = grouped[name], !members.isEmpty else { return nil }
            guard let name else {
                return MealDish(name: "", items: members.map { $0.withoutDishQuantity() })
            }
            var dish = byName[name] ?? MealDish(name: name)
            dish.items = members.map { $0.withoutDishQuantity() }
            return dish
        }
    }

    public func flattened() -> [MealItem] {
        items.map { item in
            MealItem(
                id: item.id,
                group: item.group,
                portion: item.portion,
                label: item.label,
                modelAlternatives: item.modelAlternatives,
                dish: name,
                servings: item.portion.servings * multiplier
            )
        }
    }
}
