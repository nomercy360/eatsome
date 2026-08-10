import Foundation

/// The diets that ship.
///
/// Each is a `DietSpec` and nothing more — the engine cannot tell a preset from
/// something somebody assembled from steppers last Tuesday, which is the point.
/// Switching between them re-scores the entire history instantly: recognition
/// reported food groups and grams, and no photograph is read a second time.
///
/// The stopping rule for adding one is the same as the stopping rule for adding
/// a food group: it ships when the taxonomy can actually watch it. A diet the
/// app can only pretend to score is worse than a diet it declines to offer.
public enum DietPresets {
    public static let oliveOilIsMainFatHabit = "olive-oil-main-fat"
    public static let prefersWhiteMeatHabit = "prefers-white-meat"
    /// The one goal that is not part of any preset: it is added to whichever
    /// diet is active when somebody sets a target in onboarding or settings.
    public static let proteinGoalID = "protein-target"

    public static let all: [DietSpec] = [
        mediterranean, plantForward, vegetarian, lowSugar, ketoStyle
    ]

    public static let `default` = mediterranean

    public static func preset(id: String) -> DietSpec? {
        all.first { $0.id == id }
    }

    public static func isPreset(_ id: String) -> Bool {
        all.contains { $0.id == id }
    }

    // MARK: - Mediterranean

    /// The Mediterranean Diet Adherence Screener used by the PREDIMED trial,
    /// item for item.
    ///
    /// It was the whole app until now and it is a preset now, and it loses
    /// nothing in the move: the same rules, the same thresholds, the same
    /// window, so every week ever scored still scores exactly what it scored.
    /// The only thing that changed is that it stopped being the *only* answer.
    ///
    /// It keeps the `instrument` field to itself. "Validated" means a published
    /// screener with a trial behind it, and it is the difference between a
    /// number that means something outside this app and a number that does not.
    ///
    /// The wine item is absent rather than excluded. PREDIMED awards a point for
    /// a glass of wine a day, and an app that nudges you toward drinking to
    /// raise a number is not the app being built. Scoring it again means
    /// deciding what alcohol is worth, not restoring a line.
    public static let mediterranean = DietSpec(
        id: "mediterranean",
        name: "Mediterranean",
        instrument: "MEDAS",
        goals: [
            .init(
                id: "medas-1",
                title: "Olive oil is your main culinary fat",
                plainTitle: "You cook with olive oil",
                shape: .habit(oliveOilIsMainFatHabit)
            ),
            // Scored in tablespoons by the original instrument; one serving is
            // held to be 2 tbsp, so "4 tbsp/day" becomes "2 servings/day".
            .init(
                id: "medas-2",
                title: "Olive oil ≥ 4 tbsp/day",
                plainTitle: "Olive oil, most days",
                shape: .dailyAtLeast([.oliveOil], 2.0)
            ),
            .init(
                id: "medas-3",
                title: "Vegetables ≥ 2 servings/day",
                plainTitle: "Vegetables, twice a day",
                shape: .dailyAtLeast([.vegetables], 2.0)
            ),
            .init(
                id: "medas-4",
                title: "Fruit ≥ 3 servings/day",
                plainTitle: "Fruit, three a day",
                shape: .dailyAtLeast([.fruit], 3.0)
            ),
            .init(
                id: "medas-5",
                title: "Red & processed meat < 1 serving/day",
                plainTitle: "Red and cured meat",
                shape: .dailyBelow([.redMeat, .processedMeat], 1.0)
            ),
            .init(
                id: "medas-6",
                title: "Butter, margarine or cream < 1 serving/day",
                plainTitle: "Butter and cream",
                shape: .dailyBelow([.butter], 1.0)
            ),
            .init(
                id: "medas-7",
                title: "Sugary drinks < 1/day",
                plainTitle: "Fizzy and sweet drinks",
                shape: .dailyBelow([.sugaryDrinks], 1.0)
            ),
            .init(
                id: "medas-9",
                title: "Legumes ≥ 3 servings/week",
                plainTitle: "Beans or lentils, 3 a week",
                shape: .weeklyAtLeast([.legumes], 3.0)
            ),
            .init(
                id: "medas-10",
                title: "Fish or seafood ≥ 3 servings/week",
                plainTitle: "Fish or seafood",
                shape: .weeklyAtLeast([.fish], 3.0)
            ),
            .init(
                id: "medas-11",
                title: "Sweets & pastry < 3 servings/week",
                plainTitle: "Cakes and pastry",
                shape: .weeklyBelow([.sweets, .pastry], 3.0)
            ),
            .init(
                id: "medas-12",
                title: "Nuts ≥ 3 servings/week",
                plainTitle: "Nuts",
                shape: .weeklyAtLeast([.nuts], 3.0)
            ),
            .init(
                id: "medas-13",
                title: "You prefer white meat to red meat",
                plainTitle: "You choose chicken and fish",
                shape: .habit(prefersWhiteMeatHabit)
            ),
            // Item 14 asks for sofrito by name, which is why the group existed
            // under that name at all. The food is a cooked tomato-and-onion
            // base in any kitchen; the screener's word for it lives here, where
            // it belongs, rather than in the taxonomy.
            .init(
                id: "medas-14",
                title: "Sofrito ≥ 2 servings/week",
                plainTitle: "Tomato & onion base",
                shape: .weeklyAtLeast([.cookedTomatoSauce], 2.0)
            )
        ],
        habits: [
            .init(
                id: oliveOilIsMainFatHabit,
                question: "Is olive oil your main cooking fat?",
                yes: "Olive oil",
                no: "Butter, or something else"
            ),
            .init(
                id: prefersWhiteMeatHabit,
                question: "Do you usually pick chicken or fish over red meat?",
                yes: "Mostly chicken and fish",
                no: "Mostly red meat"
            )
        ]
    )

    // MARK: - Plant-forward

    /// Not vegetarian: meat is weekly rather than forbidden, so every rule is a
    /// goal and there is nothing to break. That is the whole distinction between
    /// this and the next one, and it is why they are two presets rather than one
    /// with a switch.
    public static let plantForward = DietSpec(
        id: "plant-forward",
        name: "Plant-forward",
        goals: [
            .init(id: "pf-vegetables", title: "Vegetables ≥ 3 servings/day",
                  shape: .dailyAtLeast([.vegetables], 3.0)),
            .init(id: "pf-fruit", title: "Fruit ≥ 2 servings/day",
                  shape: .dailyAtLeast([.fruit], 2.0)),
            .init(id: "pf-legumes", title: "Legumes ≥ 5 servings/week",
                  shape: .weeklyAtLeast([.legumes], 5.0)),
            .init(id: "pf-nuts", title: "Nuts ≥ 4 servings/week",
                  shape: .weeklyAtLeast([.nuts], 4.0)),
            .init(id: "pf-plant-fats", title: "Avocado, olives or seeds ≥ 3 servings/week",
                  shape: .weeklyAtLeast([.plantFats], 3.0)),
            .init(id: "pf-whole-grains", title: "Whole grains ≥ 1 serving/day",
                  shape: .dailyAtLeast([.wholeGrains], 1.0)),
            .init(id: "pf-red-meat", title: "Red meat < 1 serving/week",
                  shape: .weeklyBelow([.redMeat], 1.0)),
            .init(id: "pf-processed-meat", title: "Processed meat < 1 serving/week",
                  shape: .weeklyBelow([.processedMeat], 1.0)),
            .init(id: "pf-dairy", title: "Dairy < 1 serving/day",
                  shape: .dailyBelow([.dairy], 1.0)),
            .init(id: "pf-sugary-drinks", title: "Sugary drinks < 1/day",
                  shape: .dailyBelow([.sugaryDrinks], 1.0))
        ]
    )

    // MARK: - Vegetarian

    /// The first preset with constraints, and the reason constraints exist.
    ///
    /// The frequency half of a vegetarian diet — beans up, nuts up, greens up —
    /// fits the old engine perfectly. The identity half did not fit it at all:
    /// `dailyBelow(meat, 0)` is strictly-less-than and can never pass, so "no
    /// meat" had no expression. And even with one, an exclusion is not a goal —
    /// "4.5 olives, but there was chicken stock in the soup" is precisely what a
    /// vegetarian wants to know and precisely what an average is built to hide.
    public static let vegetarian = DietSpec(
        id: "vegetarian",
        name: "Vegetarian",
        goals: [
            .init(id: "veg-vegetables", title: "Vegetables ≥ 2 servings/day",
                  shape: .dailyAtLeast([.vegetables], 2.0)),
            .init(id: "veg-fruit", title: "Fruit ≥ 2 servings/day",
                  shape: .dailyAtLeast([.fruit], 2.0)),
            .init(id: "veg-legumes", title: "Legumes ≥ 4 servings/week",
                  shape: .weeklyAtLeast([.legumes], 4.0)),
            .init(id: "veg-nuts", title: "Nuts ≥ 3 servings/week",
                  shape: .weeklyAtLeast([.nuts], 3.0)),
            .init(id: "veg-whole-grains", title: "Whole grains ≥ 1 serving/day",
                  shape: .dailyAtLeast([.wholeGrains], 1.0)),
            .init(id: "veg-sweets", title: "Sweets & pastry < 3 servings/week",
                  shape: .weeklyBelow([.sweets, .pastry], 3.0)),
            .init(id: "veg-sugary-drinks", title: "Sugary drinks < 1/day",
                  shape: .dailyBelow([.sugaryDrinks], 1.0))
        ],
        constraints: [
            .init(id: "veg-no-meat", title: "Meat — red, white, processed",
                  shape: .never([.redMeat, .whiteMeat, .processedMeat])),
            .init(id: "veg-no-fish", title: "Fish & seafood",
                  shape: .never([.fish]))
        ]
    )

    // MARK: - Low-sugar

    /// Everything here rules on a group or on frequency; nothing rules on a
    /// gram of sugar, because no photograph shows one and no label is on most
    /// food. "Low sugar" said in servings is a diet this app can actually watch.
    public static let lowSugar = DietSpec(
        id: "low-sugar",
        name: "Low-sugar",
        goals: [
            .init(id: "ls-sweets", title: "Sweets & pastry < 2 servings/week",
                  shape: .weeklyBelow([.sweets, .pastry], 2.0)),
            .init(id: "ls-sugary-drinks", title: "Sugary drinks < 1/week",
                  shape: .weeklyBelow([.sugaryDrinks], 1.0)),
            .init(id: "ls-juice", title: "Juice & smoothies < 2/week",
                  shape: .weeklyBelow([.juice, .smoothie], 2.0)),
            .init(id: "ls-refined-grains", title: "Refined grains < 2 servings/day",
                  shape: .dailyBelow([.refinedGrains], 2.0)),
            .init(id: "ls-whole-grains", title: "Whole grains ≥ 1 serving/day",
                  shape: .dailyAtLeast([.wholeGrains], 1.0)),
            .init(id: "ls-vegetables", title: "Vegetables ≥ 3 servings/day",
                  shape: .dailyAtLeast([.vegetables], 3.0)),
            // Whole fruit stays a goal rather than a limit. The sugar in an
            // apple arrives with the apple, and a diet that treats fruit and a
            // fizzy drink as the same problem is a diet nobody keeps.
            .init(id: "ls-fruit", title: "Fruit ≥ 2 servings/day",
                  shape: .dailyAtLeast([.fruit], 2.0))
        ]
    )

    // MARK: - Keto-style habits

    /// Named for the behaviour, never for the macro.
    ///
    /// A gram-true keto tracker means weighing food and counting carbohydrate,
    /// and this is the app that exists in order not to be that. The parser
    /// refuses to estimate carbohydrate from a photograph, and that refusal is
    /// doctrine rather than a gap: a plausible number is worse than none.
    ///
    /// What survives is the shape of the eating — grains down, sugar out,
    /// protein at every meal, fat from plants — as group frequencies, which is
    /// honest and is a proxy, and the name says so before anyone taps it. If
    /// somebody wants carb counts, that is a different product, and onboarding
    /// is a better place to say so than a support ticket.
    public static let ketoStyle = DietSpec(
        id: "keto-style",
        name: "Keto-style habits",
        goals: [
            .init(id: "keto-grains", title: "Grains < 1 serving/day",
                  shape: .dailyBelow([.wholeGrains, .refinedGrains], 1.0)),
            .init(id: "keto-sweets", title: "Sweets & pastry < 1 serving/week",
                  shape: .weeklyBelow([.sweets, .pastry], 1.0)),
            .init(id: "keto-sugary-drinks", title: "Sugary drinks < 1/week",
                  shape: .weeklyBelow([.sugaryDrinks, .juice], 1.0)),
            .init(id: "keto-fruit", title: "Fruit < 1 serving/day",
                  shape: .dailyBelow([.fruit], 1.0)),
            .init(id: "keto-plant-fats", title: "Avocado, olives or seeds ≥ 2 servings/day",
                  shape: .dailyAtLeast([.plantFats], 2.0)),
            .init(id: "keto-protein-each-meal", title: "A protein source at every meal",
                  shape: .eachMeal([.fish, .whiteMeat, .redMeat, .egg, .dairy]))
        ]
    )
}

// MARK: - The optional protein target

extension DietSpec {
    /// The one goal onboarding can bolt onto any diet.
    ///
    /// Protein is the exception to the no-macros doctrine, and it is barely an
    /// exception: the app has computed it from the same weights everything else
    /// uses for as long as it has existed, off a published composition row
    /// rather than off a model's opinion. So "protein ≥ 90 g/day" is a rule with
    /// the same provenance as "vegetables twice a day".
    ///
    /// Calories, carbohydrate and fat get no equivalent. They are computable —
    /// `FoodNutrientTable` has all five — but a *target* invites eating to a
    /// number, and the number is only as good as a weight estimated from a
    /// photograph. "Carbs down" says grains, sweets and sugary drinks down, in
    /// servings, like everything else here.
    public func withProteinTarget(_ grams: Double?) -> DietSpec {
        var copy = self
        copy.goals.removeAll { $0.id == DietPresets.proteinGoalID }
        if let grams, grams > 0 {
            copy.goals.append(
                DietGoal(
                    id: DietPresets.proteinGoalID,
                    title: "Protein ≥ \(Int(grams.rounded())) g/day",
                    plainTitle: "Protein",
                    shape: .dailyAtLeastGrams(.protein, grams)
                )
            )
        }
        return copy
    }

    /// The target currently carried, if any.
    public var proteinTarget: Double? {
        for goal in goals {
            if case .dailyAtLeastGrams(.protein, let target) = goal.shape { return target }
        }
        return nil
    }
}

// MARK: - Which choices are worth a question

/// Which rules a food group feeds, and in which direction.
///
/// Two groups with the same footprint are interchangeable as far as the score is
/// concerned: nothing about your week changes if the model called brown rice
/// white. This is what separates an ambiguity worth a tap from one that is only
/// worth a mention — and it is now computed from whichever diet is active, so a
/// low-sugar week stops being asked "fish or chicken?" and starts being asked
/// "juice or smoothie?" without a line of new code.
public struct DietFootprint: Sendable, Hashable {
    public struct Contribution: Sendable, Hashable {
        public let ruleID: String
        /// True for "less than" rules, where servings count against you, and for
        /// a `never`, where they end it.
        public let isUpperBound: Bool
    }

    public let contributions: Set<Contribution>

    /// No rule counts this group at all — `other`, and every grain under MEDAS.
    public var isUnscored: Bool { contributions.isEmpty }
}

extension DietSpec {
    public func footprint(of group: FoodGroup) -> DietFootprint {
        var contributions: Set<DietFootprint.Contribution> = []

        for goal in goals {
            switch goal.shape {
            case .dailyAtLeast(let groups, _), .weeklyAtLeast(let groups, _), .eachMeal(let groups):
                if groups.contains(group) {
                    contributions.insert(.init(ruleID: goal.id, isUpperBound: false))
                }
            case .dailyBelow(let groups, _), .weeklyBelow(let groups, _):
                if groups.contains(group) {
                    contributions.insert(.init(ruleID: goal.id, isUpperBound: true))
                }
            case .habit:
                // Answered once in settings, so no photograph can move it.
                continue
            case .dailyAtLeastGrams:
                // Deliberately not folded in, and this is the one place the
                // "diet-awareness for free" claim does not hold.
                //
                // A footprint is a pure property of a food group, and a protein
                // target is a property of a *quantity*: whether calling this
                // fish rather than chicken matters depends on whether it is a
                // 10 g garnish or a 200 g main. Contributing per group would
                // make nearly every pair of groups differ — almost every group
                // has a different protein density — so every ambiguity would
                // become score-changing, the at-most-one-question budget would
                // saturate, and the filter would stop filtering. A nutrient rule
                // needs a quantity-aware test, at a call site that has the
                // grams; see `changesNutrients(_:_:grams:)`.
                continue
            }
        }

        for constraint in constraints where constraint.isEnabled {
            if constraint.shape.groups.contains(group) {
                contributions.insert(.init(ruleID: constraint.id, isUpperBound: true))
            }
        }

        return DietFootprint(contributions: contributions)
    }

    /// True when calling this food `a` instead of `b` changes what the week
    /// scores — the test for whether a recognition ambiguity deserves a
    /// confirmation tap.
    ///
    /// Under MEDAS, white meat against red passes it (red counts against item 5,
    /// white counts nowhere) and whole against refined grains does not. Under
    /// vegetarian, red against white is a rival pair inside the *same* `never`
    /// and correctly stops being a question: the promise is broken either way,
    /// and asking which animal it was is asking a question whose answer changes
    /// nothing the person is being told.
    public func choiceChangesScore(_ a: FoodGroup, _ b: FoodGroup) -> Bool {
        guard a != b else { return false }
        return footprint(of: a) != footprint(of: b)
    }

    /// The quantity-aware half, for a diet carrying a gram target.
    ///
    /// Called only when `choiceChangesScore` has already said no: the question
    /// is then whether this particular item is big enough for the difference in
    /// protein density to matter to the target. A tenth of a day's target is the
    /// bar — below that the answer moves the meter by less than it is drawn.
    public func choiceChangesNutrients(
        _ a: FoodGroup,
        _ b: FoodGroup,
        grams: Double?,
        proteinPerServing: [String: Double] = Protein.defaultGramsPerServing,
        servingGrams: [String: Double] = ServingWeight.defaultGrams
    ) -> Bool {
        guard a != b, let grams, let target = proteinTarget, target > 0 else { return false }
        func protein(_ group: FoodGroup) -> Double {
            let servings = ServingWeight.servings(fromGrams: grams, of: group, table: servingGrams)
            return (group.value(in: proteinPerServing) ?? 0) * servings
        }
        return abs(protein(a) - protein(b)) >= target / 10
    }
}
