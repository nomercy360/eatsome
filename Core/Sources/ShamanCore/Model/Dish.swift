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
    /// Kilocalories, for one serving as printed.
    ///
    /// This was kept and never summed for two years, because only packaged food
    /// carries a label and a total built from these would have been computed
    /// from the packaged fraction of a meal while looking exactly like a total.
    /// What changed is the baseline underneath, not the argument: every food now
    /// derives energy from `FoodNutrientTable`, so a printed figure improves a
    /// complete total rather than creating a partial one — which is the test
    /// `Protein` had to pass to be totalled in the first place.
    public var calories: Double?
    public var fat: Double?
    public var carbohydrate: Double?
    /// Grams of salt equivalent, as Japanese labels print it. `sodium` is
    /// derived from it by the backend when only salt was printed.
    public var salt: Double?
    /// GRAMS, not milligrams — this field mirrors what a label prints and what
    /// `nutritionPanelSchema` caps at 100, and the backend derives it from
    /// `salt` in grams. `Nutrients.sodium` is milligrams, because that is the
    /// unit composition tables publish; anything moving a figure between the two
    /// multiplies by 1000. See `Nutrition.total(in:)`.
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
/// ingredients underneath drive the nutrition figures and meal rating. The quantity is on
/// the ingredients, as weight: `count` is how many servings are present, but it
/// is a label and a control rather than a factor, since the weights below
/// already cover every serving there is.
public struct MealDish: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public var name: String
    /// How many servings of this dish. Three beers is one dish with count 3.
    public var count: Int
    /// How big ONE serving is, on a meal old enough to be described in portions.
    ///
    /// Nothing sets this any more: no model is asked for it and the dish sheet
    /// stopped offering the chips in v17, because on a weighed dish the control
    /// changed no quantity — `effectiveServings` prefers grams — while looking
    /// exactly like one that did. It stays on the type so a meal logged before
    /// August 2026 still reads the way it did the day it was logged.
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
    /// quantity is applied. Only meaningful for a dish described in portions —
    /// see `weighed`.
    public var multiplier: Double { Double(count) * size.servings }

    /// True when recognition weighed this dish's ingredients.
    ///
    /// A weighed ingredient's `grams` is everything of it on the plate, so the
    /// dish's own `count` and `size` must not be applied on top: three beers
    /// arrive as one dish with the grams of three beers already in it. Changing
    /// `count` in the UI rewrites those grams instead — see `scaled(toCount:)`.
    /// Multiplying anyway is the same mistake that made one bowl of ramen worth
    /// 126 g of protein, and on 220 weighed dishes it cost 7 points of median
    /// error and half again as many gross misses.
    public var weighed: Bool { items.contains { $0.grams != nil } }

    /// The dish as if a different number of servings had been present. Used by
    /// the count control, which now rewrites weights rather than multiplying
    /// them when calculating quantities.
    public func scaled(toCount newCount: Int) -> MealDish {
        guard weighed, count > 0, newCount > 0, newCount != count else {
            var copy = self
            copy.count = max(1, newCount)
            return copy
        }
        let factor = Double(newCount) / Double(count)
        var copy = self
        copy.count = newCount
        copy.items = items.map { item in
            var scaled = item
            if let grams = item.grams { scaled.grams = grams * factor }
            return scaled
        }
        return copy
    }

    /// The dish as ingredient rows, each carrying the servings the three
    /// factors produced.
    ///
    /// `MealEntry` stores both this and the dishes, so that a build which has
    /// never heard of dishes still reads a meal correctly. They can only
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
                kind: item.kind,
                portion: item.portion,
                label: item.label,
                modelAlternatives: item.modelAlternatives,
                preparation: item.preparation,
                compositionHints: item.compositionHints,
                resolution: item.resolution,
                dish: name,
                // A weighed ingredient already says how much is there. Writing a
                // `servings` beside it would be a second answer to the same
                // question, and `effectiveServings` prefers grams anyway — so
                // the only way they could ever disagree is if this wrote one.
                servings: item.grams == nil ? item.portion.servings * multiplier : nil,
                grams: item.grams
            )
        }
    }
}
