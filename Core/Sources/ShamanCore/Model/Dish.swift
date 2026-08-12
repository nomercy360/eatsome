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
/// The dish is what a person recognises — "kaisen don", "two beers". The
/// quantity lives on the ingredients as weight; `count` is a label and a
/// control, never a factor, because the weights below already cover every
/// serving present. Changing it rewrites them — see `scaled(toCount:)`.
///
/// v20 also carried `size` and a `multiplier`, and multiplying a weighed dish
/// by both is what made one bowl of ramen worth 126 g of protein. There is no
/// multiplier here at all: with weights absolute and composition stored, a dish
/// total is a sum.
public struct MealDish: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// What it is called. Nil for food assembled by hand that belongs to no
    /// named dish — the picker offers ingredients, not dishes.
    public var name: String?
    /// How many servings of this dish are present. Three beers is one dish with
    /// count 3, and the ingredient weights already account for all three.
    public var count: Int
    /// What the packaging said, when it said anything. Nil for almost all food,
    /// which is cooked and has nothing printed on it.
    public var panel: NutritionPanel?
    public var items: [MealItem]

    public init(
        id: UUID = UUIDv7.generate(),
        name: String? = nil,
        count: Int = 1,
        panel: NutritionPanel? = nil,
        items: [MealItem] = []
    ) {
        self.id = id
        self.name = name
        self.count = count
        self.panel = panel
        self.items = items
    }

    public var grams: Double { items.reduce(0) { $0 + $1.grams } }

    /// The dish total: its ingredients summed, then any printed figure
    /// substituted in.
    ///
    /// Figure by figure rather than wholesale, which is the same rule v20 had
    /// and the same reason: a carton printing protein and energy but no sodium
    /// contributes two read numbers and three from the model, and discarding the
    /// ingredients over a partial panel throws away something true.
    public var nutrients: Nutrients {
        var total = items.reduce(Nutrients.zero) { $0 + $1.nutrients }
        guard let panel else { return total }
        if let value = panel.protein { total.protein = value }
        if let value = panel.fat { total.fat = value }
        if let value = panel.carbohydrate { total.carbohydrate = value }
        if let value = panel.calories { total.kcal = value }
        // The panel prints grams of salt or grams of sodium; `Nutrients.sodium`
        // is milligrams. Salt is preferred when both are present because it is
        // what the label was actually counted in outside the United States.
        if let salt = panel.salt {
            total.sodium = salt * 1000 / Nutrients.saltPerSodium
        } else if let sodium = panel.sodium {
            total.sodium = sodium * 1000
        }
        return total
    }

    /// Which of the five this dish's panel settled, so a caller can mark them
    /// read rather than estimated without re-deriving the rule above.
    public var panelSources: NutrientProvenance? {
        guard let panel else { return nil }
        var sources = NutrientProvenance.model
        if panel.protein != nil { sources.protein = .panel }
        if panel.fat != nil { sources.fat = .panel }
        if panel.carbohydrate != nil { sources.carbohydrate = .panel }
        if panel.calories != nil { sources.kcal = .panel }
        if panel.salt != nil || panel.sodium != nil { sources.sodium = .panel }
        return sources
    }

    /// The dish as if a different number of servings had been present.
    ///
    /// Rewrites the weights rather than multiplying at score time, so there is
    /// never a second place where quantity lives.
    public func scaled(toCount newCount: Int) -> MealDish {
        var copy = self
        copy.count = max(1, newCount)
        guard count > 0, copy.count != count else { return copy }
        let factor = Double(copy.count) / Double(count)
        copy.items = items.map { $0.weighing($0.grams * factor) }
        return copy
    }

    /// Replace one item wherever it lives, by id. Corrections address rows, and
    /// with the flat list gone this is how they land.
    public func replacing(_ item: MealItem) -> MealDish {
        guard items.contains(where: { $0.id == item.id }) else { return self }
        var copy = self
        copy.items = items.map { $0.id == item.id ? item : $0 }
        return copy
    }

    public func removing(_ itemID: UUID) -> MealDish {
        var copy = self
        copy.items = items.filter { $0.id != itemID }
        return copy
    }
}
