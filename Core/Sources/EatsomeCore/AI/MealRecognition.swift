import Foundation

// The recognition response, as it arrives from the Worker.
//
// These are wire types: they spell fields the way `Backend/src/contracts.ts`
// does (`per_100g`, `duration_minutes`, `calories`) and they exist to be
// decoded once and turned into the stored types in `Model/`. Nothing here is
// stored. The conversions at the bottom are the only place the wire shape and
// the stored shape meet, so a field that changes on one side fails to compile
// or fails to decode here, in one file, rather than drifting silently.
//
// One rule governs the whole file: the schema is the enforcement and the
// prompt is the reminder. Both providers emit exactly the properties their
// schema names, so what a type here *cannot* carry is as deliberate as what it
// can.

/// A printed panel, as transcribed. Every field nullable because a panel is
/// routinely partial and an unreadable figure must come back absent, not zero.
///
/// `calories` on the wire, `kcal` in storage — the label's word and ours.
public struct RecognizedPanel: Decodable, Sendable, Hashable {
    public var protein: Double?
    public var calories: Double?
    public var fat: Double?
    public var carbohydrate: Double?
    /// Grams of salt equivalent, which is what labels outside the US print.
    /// Separate from `sodium` because a model given only one field converts
    /// into it silently, and a converted figure is indistinguishable from a
    /// read one.
    public var salt: Double?
    public var sodium: Double?
    /// Grams of alcohol when a label prints it. Most print ABV instead, which
    /// is not this field: a percentage by volume is not grams in the container.
    public var alcohol: Double?
    /// Milligrams, as printed. Never an estimate — that is `caffeine_mg` on the
    /// composition block.
    public var caffeine: Double?
    /// What the figures are counted against, copied from the heading above
    /// them. A number without this has no unit.
    public var basis: String?
    public var net_ml: Double?
    public var net_g: Double?

    /// The stored panel, or nil when the figures cannot honestly be attached to
    /// what is on the plate.
    ///
    /// A `per_serving` or `per_container` panel describes the thing itself. A
    /// `per_100ml` or `per_100g` one describes a hundred units of it, and
    /// without a printed net weight there is nothing to scale it by — so it is
    /// dropped rather than filed against the can as though it were the can.
    public var stored: NutritionPanel? {
        guard let basis, let factor = Self.factor(basis: basis, netML: net_ml, netG: net_g) else {
            return nil
        }
        let panel = NutritionPanel(
            kcal: calories.map { $0 * factor },
            protein: protein.map { $0 * factor },
            fat: fat.map { $0 * factor },
            carbohydrate: carbohydrate.map { $0 * factor },
            salt: salt.map { $0 * factor },
            sodium: sodium.map { $0 * factor },
            alcohol: alcohol.map { $0 * factor },
            caffeine: caffeine.map { $0 * factor }
        )
        return panel.isEmpty ? nil : panel
    }

    /// What to multiply the printed figures by to get the container.
    ///
    /// A `per_serving` or `per_container` panel already describes the thing, so
    /// the factor is 1. A `per_100ml` or `per_100g` one describes a hundred
    /// units of it and is only usable if the package also printed how much is
    /// in it — `carbohydrate: 1` is true per 100 ml of a Monster and wrong by
    /// 3.55× for the can, and nothing downstream can tell the difference. With
    /// the net printed, this is arithmetic the app can do and the model should
    /// not; without it, nil, because filing a per-100 figure against the can is
    /// the confident wrong number.
    private static func factor(basis: String, netML: Double?, netG: Double?) -> Double? {
        switch basis {
        case "per_serving", "per_container": 1
        case "per_100ml": netML.flatMap { $0 > 0 ? $0 / 100 : nil }
        case "per_100g": netG.flatMap { $0 > 0 ? $0 / 100 : nil }
        default: nil
        }
    }
}

/// One food, as the model named and priced it.
public struct RecognizedIngredient: Decodable, Sendable, Hashable {
    public var label: String
    /// Edible weight present, absolute, across every serving. Nothing
    /// multiplies it by the dish's count afterwards.
    public var grams: Double
    public var per_100g: Nutrients
    public var preparation: [PreparationMethod]
    public var alternatives: [RecognizedAlternative]
    /// The chain whose menu item this row *is*. Null for everything cooked,
    /// served loose, or added on top of one.
    public var brand: String?
    public var sizes: [RecognizedSize]

    public var stored: MealItem {
        MealItem(
            label: label,
            preparation: preparation,
            grams: grams,
            per100g: per_100g,
            provenance: .model,
            alternatives: alternatives.map(\.stored),
            brand: brand?.isEmpty == true ? nil : brand,
            sizes: sizes.map(\.stored)
        )
    }
}

/// A priced, weighed rival. Weighed as well as priced because a rival menu item
/// is not the same size as the one first guessed: a tuna sub priced at whatever
/// the turkey sub weighed is a number that looks chosen and is not.
public struct RecognizedAlternative: Decodable, Sendable, Hashable {
    public var label: String
    public var per_100g: Nutrients
    public var grams: Double

    public init(label: String, per_100g: Nutrients, grams: Double) {
        self.label = label
        self.per_100g = per_100g
        self.grams = grams
    }

    public var stored: FoodAlternative {
        FoodAlternative(label: label, per100g: per_100g, grams: grams)
    }
}

/// One size a chain sells an item in, priced in full.
///
/// `basis` says whether the chain printed this size's figures or whether they
/// are arithmetic on another size — a Footlong is usually double a Regular and
/// nobody prints it, which makes it the size most likely to be wrong.
public struct RecognizedSize: Decodable, Sendable, Hashable {
    public var label: String
    public var grams: Double
    public var per_100g: Nutrients
    public var basis: String

    public var stored: FoodSize {
        FoodSize(label: label, grams: grams, per100g: per_100g)
    }
}

/// One named thing on the tray, and what it is made of.
///
/// `count` is how many servings are present, and it is a label rather than a
/// factor: the ingredients already weigh every serving that is there.
public struct RecognizedDish: Decodable, Sendable, Hashable {
    public var name: String
    public var count: Int
    public var panel: RecognizedPanel?
    public var ingredients: [RecognizedIngredient]

    public var stored: MealDish {
        MealDish(
            name: name,
            count: count,
            panel: panel?.stored,
            items: ingredients.map(\.stored)
        )
    }
}

/// What the Worker returns for one message.
///
/// One list, because there is one thing a recognition can contain. It briefly
/// also carried activities and a declared `entry` kind naming which of the two
/// a message was, and both went when activities left the release: reading
/// "sauna, twenty minutes" out of a sentence needs a vocabulary, a mapping and
/// a fallback before it can be grouped with the next sauna, and the feature
/// was cut rather than shipped half-answered.
public struct MealRecognition: Decodable, Sendable, Hashable {
    public let dishes: [RecognizedDish]

    public init(dishes: [RecognizedDish]) {
        self.dishes = dishes
    }

    /// Nothing was found. The model was sent words or a photograph and came
    /// back with no food in it — which is the "Couldn't read it" screen's
    /// whole signal, and is why it is a plain empty list rather than a
    /// declared kind: there is only one thing a recognition can contain now,
    /// so its absence needs no name.
    public var isEmpty: Bool { dishes.isEmpty }

    /// The meal, when there is one. Nil rather than a meal of no dishes: a
    /// meal worth zero calories that looks logged is the confident wrong
    /// number the rest of the app is arranged against.
    public func mealEntry(
        eatenAt: EpochMillis,
        source: MealSource,
        photoHash: String? = nil,
        note: String? = nil,
        messageID: UUID? = nil,
        id: UUID = UUIDv7.generate()
    ) -> MealEntry? {
        guard !dishes.isEmpty else { return nil }
        return MealEntry(
            id: id,
            eatenAt: eatenAt,
            dishes: dishes.map(\.stored),
            source: source,
            photoHash: photoHash,
            note: note,
            messageID: messageID
        )
    }

}
