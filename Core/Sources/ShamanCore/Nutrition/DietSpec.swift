import Foundation

/// A diet is a named list of rules. Nothing in this file knows what
/// "Mediterranean" means.
///
/// That was already almost true: `Medas.items` was fourteen frequency rules over
/// food groups evaluated by an engine that never mentioned the Mediterranean,
/// and recognition reports groups and grams without scoring anything. What was
/// hardcoded was the *list*, not the machinery. So a diet becomes data the user
/// owns, presets ship as specs, and switching re-scores the whole history
/// instantly with no photograph re-read: one parse, many verdicts.
///
/// The type draws one distinction the old list could not:
///
/// - **Goals** are frequency rules. They average into the score, which is what a
///   score is for — "four of five, and Thursday was thin" is a description of a
///   week, not a verdict on it.
/// - **Constraints** are kept or broken. A vegetarian who scores 4.5 olives and
///   finds chicken stock in the soup cares about the stock, and an average is
///   exactly the instrument that hides it. They are a separate array rather than
///   a flag on a rule so that no amount of later carelessness can average one:
///   the type says which.
public struct DietSpec: Codable, Sendable, Hashable, Identifiable {
    /// Stable, and never localized: it is the on-disk identity of the diet a
    /// week was scored under. Presets use their own slug; a fork gets a UUIDv7
    /// string.
    public let id: String
    public var name: String
    /// The published instrument this spec reproduces, if it reproduces one.
    ///
    /// Exactly one preset may carry a value here today, and the badge on the
    /// picker is drawn from this field rather than from the name — "validated"
    /// is a claim about provenance, and a diet somebody assembled from steppers
    /// last Tuesday must not be able to make it by calling itself MEDAS.
    public var instrument: String?
    /// The spec this was forked from, for the "forked from Vegetarian" subtitle.
    /// Nil on a preset and on a diet started blank.
    public var forkedFrom: String?
    public var goals: [DietGoal]
    public var constraints: [DietConstraint]
    /// The questions this diet needs answered that no photograph can settle.
    /// Asked once in onboarding, changeable in settings, and referenced by the
    /// `.habit` goals below.
    public var habits: [DietHabitQuestion]

    public init(
        id: String,
        name: String,
        instrument: String? = nil,
        forkedFrom: String? = nil,
        goals: [DietGoal],
        constraints: [DietConstraint] = [],
        habits: [DietHabitQuestion] = []
    ) {
        self.id = id
        self.name = name
        self.instrument = instrument
        self.forkedFrom = forkedFrom
        self.goals = goals
        self.constraints = constraints
        self.habits = habits
    }

    /// What the picker row says under the name: "12 rules + 2 habits".
    public var ruleSummary: String {
        var parts: [String] = []
        let habitGoals = goals.count { if case .habit = $0.shape { return true } else { return false } }
        let ruleCount = goals.count - habitGoals
        if constraints.isEmpty {
            parts.append("\(ruleCount) rule\(ruleCount == 1 ? "" : "s")")
        } else {
            parts.append("\(ruleCount) goal\(ruleCount == 1 ? "" : "s")")
            parts.append("\(constraints.count) constraint\(constraints.count == 1 ? "" : "s")")
        }
        if habitGoals > 0 { parts.append("\(habitGoals) habit\(habitGoals == 1 ? "" : "s")") }
        return parts.joined(separator: " + ")
    }

    public func goal(id: String) -> DietGoal? { goals.first { $0.id == id } }

    /// A copy under a new identity, which is what "fork a preset" means: the
    /// rules are yours from that moment and the instrument claim does not come
    /// with them.
    public func forked(as name: String, id: String = UUIDv7.generate().uuidString) -> DietSpec {
        DietSpec(
            id: id,
            name: name,
            instrument: nil,
            forkedFrom: self.id,
            goals: goals,
            constraints: constraints,
            habits: habits
        )
    }
}

// MARK: - Goals

/// One rule that averages into the score.
public struct DietGoal: Codable, Sendable, Hashable, Identifiable {
    /// Stable within a spec. Copy, exclusions and "which rules moved this week"
    /// all key on it, so renaming one is a different rule rather than the same
    /// rule renamed.
    public let id: String
    /// The screener's own phrasing — "Fish or seafood ≥ 3 servings/week". Right
    /// in a methods note, wrong on a card someone reads before lunch, which is
    /// what `DietCopy` is for.
    public var title: String
    /// Overrides the sentence `DietCopy` would generate from the shape. Set on
    /// the MEDAS preset, where fourteen hand-written lines already read better
    /// than any template will, and nil on everything a person builds — a rule
    /// assembled from a stepper has no copy nobody wrote.
    public var plainTitle: String?
    public var shape: Shape

    public init(id: String, title: String, plainTitle: String? = nil, shape: Shape) {
        self.id = id
        self.title = title
        self.plainTitle = plainTitle
        self.shape = shape
    }

    /// The five original shapes plus the two the stress test earned.
    ///
    /// `eachMeal` and `dailyAtLeastGrams` are here rather than in
    /// `DietConstraint` because both are goals in the ordinary sense: missing
    /// protein at breakfast is a thinner day, not a broken promise.
    public enum Shape: Sendable, Hashable {
        /// Average servings per day across the window is at or above the threshold.
        case dailyAtLeast([FoodGroup], Double)
        /// Average servings per day across the window is strictly below the threshold.
        case dailyBelow([FoodGroup], Double)
        /// Servings across the window, rescaled to 7 days, at or above the threshold.
        case weeklyAtLeast([FoodGroup], Double)
        case weeklyBelow([FoodGroup], Double)
        /// Answered once in settings, not derivable from photographs. The string
        /// is a `DietHabitQuestion.id` on the same spec.
        case habit(String)
        /// Every meal in the window carries at least one of these groups.
        ///
        /// The engine summed day totals before this existed, so three yoghurts
        /// at breakfast satisfied "a protein source every meal" — which is the
        /// one thing the rule is about. It unlocks a family: vegetables with
        /// every lunch and dinner, no dessert with a weekday meal.
        case eachMeal([FoodGroup])
        /// Average grams per day at or above the threshold.
        ///
        /// The single exception to "nothing asks a model for a number except a
        /// weight", and it is not an exception at all: protein is `grams × per
        /// 100 g` off a published composition row, exactly the arithmetic the
        /// app has always done. See `DietNutrient` for why there is one case.
        case dailyAtLeastGrams(DietNutrient, Double)

        /// True when servings count against you — the direction a meter has to
        /// be drawn in, and the reason "eat less cake" never appears as advice.
        public var isUpperBound: Bool {
            switch self {
            case .dailyBelow, .weeklyBelow: true
            default: false
            }
        }

        /// The groups this rule watches. Empty for a habit, which watches an
        /// answer, and for a nutrient, which watches a total.
        public var groups: [FoodGroup] {
            switch self {
            case .dailyAtLeast(let g, _), .dailyBelow(let g, _),
                 .weeklyAtLeast(let g, _), .weeklyBelow(let g, _),
                 .eachMeal(let g):
                g
            case .habit, .dailyAtLeastGrams:
                []
            }
        }

        /// What the rule asks for, in its own unit. One for a habit and for
        /// `eachMeal`, both of which are all-or-nothing.
        public var target: Double {
            switch self {
            case .dailyAtLeast(_, let t), .dailyBelow(_, let t),
                 .weeklyAtLeast(_, let t), .weeklyBelow(_, let t),
                 .dailyAtLeastGrams(_, let t):
                t
            case .habit, .eachMeal:
                1
            }
        }

        /// The same rule with a different threshold — what the editor's stepper
        /// produces. Shapes with no threshold come back unchanged.
        public func withTarget(_ value: Double) -> Shape {
            switch self {
            case .dailyAtLeast(let g, _): .dailyAtLeast(g, value)
            case .dailyBelow(let g, _): .dailyBelow(g, value)
            case .weeklyAtLeast(let g, _): .weeklyAtLeast(g, value)
            case .weeklyBelow(let g, _): .weeklyBelow(g, value)
            case .dailyAtLeastGrams(let n, _): .dailyAtLeastGrams(n, value)
            case .habit, .eachMeal: self
            }
        }

        /// Whether the threshold is stated per day or per week, for the stepper
        /// label. Nil where there is no threshold to state.
        public var cadence: DietCadence? {
            switch self {
            case .dailyAtLeast, .dailyBelow: .daily
            case .weeklyAtLeast, .weeklyBelow: .weekly
            case .dailyAtLeastGrams: .daily
            case .habit, .eachMeal: nil
            }
        }
    }
}

public enum DietCadence: String, Codable, Sendable, Hashable {
    case daily
    case weekly

    /// "3 / day", "4 / wk" — the middle of the stepper.
    public var suffix: String {
        switch self {
        case .daily: "day"
        case .weekly: "wk"
        }
    }
}

/// The one nutrient a diet may state a gram target for.
///
/// One case, deliberately. Protein is computable from the same weights
/// everything else uses, and the app has shown a protein total for years.
/// Energy, carbohydrate and fat are computable too — `FoodNutrientTable` has
/// them — but a *target* is a different claim from a total: it invites eating to
/// a number, and the number is `grams × per 100 g` off a coarse composition row
/// rather than a measurement. "Carbs down" says grains, sweets and sugary drinks
/// down, in servings, like every other rule here. Adding a case is a decision to
/// be argued, which is what an enum with one case is for.
public enum DietNutrient: String, Codable, Sendable, Hashable, CaseIterable {
    case protein

    public var displayName: String {
        switch self {
        case .protein: "Protein"
        }
    }

    public var unit: String { "g" }
}

// MARK: - Constraints

/// A rule that is kept or broken, and never averaged.
///
/// Its own type rather than a case of `DietGoal.Shape` so that the split is
/// structural. A vegetarian's "no meat" is not 1/14th of a week — it is the
/// thing they would want to know about even on a week that scored five olives,
/// with the dish named, which is exactly what an average is built to lose.
public struct DietConstraint: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public var title: String
    public var shape: Shape
    /// Off keeps the constraint in the spec and stops it being evaluated — what
    /// the editor's toggle writes. A deleted constraint loses its history;
    /// a disabled one is still there when you turn it back on.
    public var isEnabled: Bool

    public init(id: String, title: String, shape: Shape, isEnabled: Bool = true) {
        self.id = id
        self.title = title
        self.shape = shape
        self.isEnabled = isEnabled
    }

    public enum Shape: Sendable, Hashable {
        /// None of these groups, ever.
        ///
        /// Not `dailyBelow(groups, 0)`: that check is strictly-less-than and can
        /// never pass, so exclusion had no expression at all in the old shapes.
        case never([FoodGroup])
        /// Eating happens between these two local hours. 16:8 fasting is
        /// `eatingWindow(12, 20)`.
        ///
        /// Says nothing about food and everything about time — a dimension the
        /// rules did not have and the data always did, since every meal carries
        /// `eatenAt`. Backdated logging makes that user-asserted, which is fine:
        /// the app trusts the eater everywhere else too.
        case eatingWindow(startHour: Double, endHour: Double)

        public var groups: [FoodGroup] {
            switch self {
            case .never(let g): g
            case .eatingWindow: []
            }
        }
    }
}

/// A question a photograph cannot answer, asked once.
///
/// Carried by the spec rather than hardcoded, because "is olive oil your main
/// cooking fat" is a Mediterranean question and a low-sugar diet has no use for
/// it. `id` is what a `.habit` goal names and what `DietHabits` stores under.
public struct DietHabitQuestion: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// The question, as asked: "Is olive oil your main cooking fat?"
    public var question: String
    /// The affirmative answer said out loud, for the two-button row.
    public var yes: String
    public var no: String
    /// What a person who has not answered gets. The commonest answer, so that
    /// skipping onboarding does not silently cost a point.
    public var defaultAnswer: Bool

    public init(
        id: String,
        question: String,
        yes: String = "Yes",
        no: String = "No",
        defaultAnswer: Bool = true
    ) {
        self.id = id
        self.question = question
        self.yes = yes
        self.no = no
        self.defaultAnswer = defaultAnswer
    }
}

// MARK: - On-disk format

// Hand-written rather than synthesized, for the same reason `EventPayload` is: a
// spec is written into an append-only log, and `{"dailyAtLeast":{"_0":[…]}}` is
// a shape nobody can read in a year and nothing else can produce. `kind` plus
// named fields is the format; an unknown `kind` throws here and is caught one
// level up, where a spec that will not decode falls back to the preset rather
// than taking the log down with it.

extension DietGoal.Shape: Codable {
    private enum CodingKeys: String, CodingKey { case kind, groups, target, habit, nutrient }

    private enum Kind: String, Codable {
        case dailyAtLeast = "daily_at_least"
        case dailyBelow = "daily_below"
        case weeklyAtLeast = "weekly_at_least"
        case weeklyBelow = "weekly_below"
        case habit
        case eachMeal = "each_meal"
        case dailyAtLeastGrams = "daily_at_least_grams"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func groups() throws -> [FoodGroup] { try c.decode([FoodGroup].self, forKey: .groups) }
        func target() throws -> Double { try c.decode(Double.self, forKey: .target) }

        switch try c.decode(Kind.self, forKey: .kind) {
        case .dailyAtLeast: self = .dailyAtLeast(try groups(), try target())
        case .dailyBelow: self = .dailyBelow(try groups(), try target())
        case .weeklyAtLeast: self = .weeklyAtLeast(try groups(), try target())
        case .weeklyBelow: self = .weeklyBelow(try groups(), try target())
        case .habit: self = .habit(try c.decode(String.self, forKey: .habit))
        case .eachMeal: self = .eachMeal(try groups())
        case .dailyAtLeastGrams:
            self = .dailyAtLeastGrams(try c.decode(DietNutrient.self, forKey: .nutrient), try target())
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        func write(_ kind: Kind, _ groups: [FoodGroup], _ target: Double?) throws {
            try c.encode(kind, forKey: .kind)
            try c.encode(groups, forKey: .groups)
            if let target { try c.encode(target, forKey: .target) }
        }
        switch self {
        case .dailyAtLeast(let g, let t): try write(.dailyAtLeast, g, t)
        case .dailyBelow(let g, let t): try write(.dailyBelow, g, t)
        case .weeklyAtLeast(let g, let t): try write(.weeklyAtLeast, g, t)
        case .weeklyBelow(let g, let t): try write(.weeklyBelow, g, t)
        case .eachMeal(let g): try write(.eachMeal, g, nil)
        case .habit(let id):
            try c.encode(Kind.habit, forKey: .kind)
            try c.encode(id, forKey: .habit)
        case .dailyAtLeastGrams(let nutrient, let t):
            try c.encode(Kind.dailyAtLeastGrams, forKey: .kind)
            try c.encode(nutrient, forKey: .nutrient)
            try c.encode(t, forKey: .target)
        }
    }
}

extension DietConstraint.Shape: Codable {
    private enum CodingKeys: String, CodingKey { case kind, groups, startHour, endHour }

    private enum Kind: String, Codable {
        case never
        case eatingWindow = "eating_window"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .never:
            self = .never(try c.decode([FoodGroup].self, forKey: .groups))
        case .eatingWindow:
            self = .eatingWindow(
                startHour: try c.decode(Double.self, forKey: .startHour),
                endHour: try c.decode(Double.self, forKey: .endHour)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .never(let g):
            try c.encode(Kind.never, forKey: .kind)
            try c.encode(g, forKey: .groups)
        case .eatingWindow(let start, let end):
            try c.encode(Kind.eatingWindow, forKey: .kind)
            try c.encode(start, forKey: .startHour)
            try c.encode(end, forKey: .endHour)
        }
    }
}
