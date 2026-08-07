import Foundation

/// The app stores an append-only log of events, never mutable rows.
///
/// Two reasons. First, a correction is itself information — "the model said
/// white meat, I said fish" is the data that tells you whether the recognition
/// prompt needs work, and an UPDATE destroys it. Second, syncing an append-only
/// log to a server later is a concatenate-and-sort; syncing mutable state is a
/// conflict-resolution problem. That is the difference between adding a backend
/// in a day and adding one in a week.
public struct LoggedEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    /// When the thing happened in the world.
    public let occurredAt: EpochMillis
    /// When we wrote it down. Differs from `occurredAt` when you log lunch at 9pm.
    public let recordedAt: EpochMillis
    public let payload: EventPayload

    public init(
        id: UUID = UUIDv7.generate(),
        occurredAt: EpochMillis,
        recordedAt: EpochMillis = Date().epochMillis,
        payload: EventPayload
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.payload = payload
    }
}

public enum EventPayload: Sendable, Hashable {
    case mealLogged(MealEntry)
    /// Supersedes an earlier `mealLogged` with the same meal id.
    case mealRevised(MealEntry)
    case mealDeleted(mealID: UUID)
    case setCompleted(SetRecord)
    case habitsUpdated(DietHabits)
    /// Also the edit: a recipe saved under an existing id supersedes it, the
    /// same way `mealRevised` supersedes a meal.
    case recipeSaved(Recipe)
    case recipeDeleted(recipeID: UUID)
}

// Hand-written coding rather than the synthesized `{"mealLogged":{"_0":...}}`
// shape: this is an on-disk format we intend to still be able to read in a year,
// and an unknown `kind` must degrade to "skip this line", not "fail the file".
extension EventPayload: Codable {
    private enum CodingKeys: String, CodingKey { case kind, data }

    private enum Kind: String, Codable {
        case mealLogged = "meal_logged"
        case mealRevised = "meal_revised"
        case mealDeleted = "meal_deleted"
        case setCompleted = "set_completed"
        case habitsUpdated = "habits_updated"
        case recipeSaved = "recipe_saved"
        case recipeDeleted = "recipe_deleted"
    }

    private struct MealRef: Codable { let mealID: UUID }
    private struct RecipeRef: Codable { let recipeID: UUID }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .mealLogged: self = .mealLogged(try c.decode(MealEntry.self, forKey: .data))
        case .mealRevised: self = .mealRevised(try c.decode(MealEntry.self, forKey: .data))
        case .mealDeleted: self = .mealDeleted(mealID: try c.decode(MealRef.self, forKey: .data).mealID)
        case .setCompleted: self = .setCompleted(try c.decode(SetRecord.self, forKey: .data))
        case .habitsUpdated: self = .habitsUpdated(try c.decode(DietHabits.self, forKey: .data))
        case .recipeSaved: self = .recipeSaved(try c.decode(Recipe.self, forKey: .data))
        case .recipeDeleted: self = .recipeDeleted(recipeID: try c.decode(RecipeRef.self, forKey: .data).recipeID)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .mealLogged(let m):
            try c.encode(Kind.mealLogged, forKey: .kind); try c.encode(m, forKey: .data)
        case .mealRevised(let m):
            try c.encode(Kind.mealRevised, forKey: .kind); try c.encode(m, forKey: .data)
        case .mealDeleted(let id):
            try c.encode(Kind.mealDeleted, forKey: .kind); try c.encode(MealRef(mealID: id), forKey: .data)
        case .setCompleted(let s):
            try c.encode(Kind.setCompleted, forKey: .kind); try c.encode(s, forKey: .data)
        case .habitsUpdated(let h):
            try c.encode(Kind.habitsUpdated, forKey: .kind); try c.encode(h, forKey: .data)
        case .recipeSaved(let r):
            try c.encode(Kind.recipeSaved, forKey: .kind); try c.encode(r, forKey: .data)
        case .recipeDeleted(let id):
            try c.encode(Kind.recipeDeleted, forKey: .kind); try c.encode(RecipeRef(recipeID: id), forKey: .data)
        }
    }
}

/// The in-memory read model. The log is the truth; this is a fold over it.
/// A personal tracker accumulates a few thousand events a year, so replaying
/// the whole log on launch costs milliseconds and buys us a store with no
/// migration story to maintain.
public struct Projection: Sendable {
    public private(set) var meals: [UUID: MealEntry] = [:]
    public private(set) var sets: [SetRecord] = []
    public private(set) var habits = DietHabits()
    public private(set) var recipes: [UUID: Recipe] = [:]

    public init() {}

    public init(replaying events: some Sequence<LoggedEvent>) {
        self.init()
        for event in events { apply(event) }
    }

    public mutating func apply(_ event: LoggedEvent) {
        switch event.payload {
        case .mealLogged(let m), .mealRevised(let m): meals[m.id] = m
        case .mealDeleted(let id): meals.removeValue(forKey: id)
        case .setCompleted(let s): sets.append(s)
        case .habitsUpdated(let h): habits = h
        case .recipeSaved(let r): recipes[r.id] = r
        case .recipeDeleted(let id): recipes.removeValue(forKey: id)
        }
    }

    /// Most recently saved or used first — the dish you cooked yesterday is the
    /// one you are most likely cooking now.
    public var recentRecipes: [Recipe] {
        recipes.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// The quickest saved-dish choices for the meal chooser.
    ///
    /// Once a dish has actually been logged, frequency is the strongest signal:
    /// it is more useful to offer lentil soup for the twelfth time than a recipe
    /// that was merely edited yesterday. Before any saved dish has been reused,
    /// there is no frequency signal, so the most recently saved dishes are the
    /// honest fallback. Unused dishes do not displace established favourites.
    public func suggestedRecipes(limit: Int) -> [Recipe] {
        guard limit > 0 else { return [] }

        let uses = Dictionary(grouping: meals.values.compactMap(\.recipeID), by: { $0 })
            .mapValues(\.count)
        let used = recipes.values.filter { uses[$0.id, default: 0] > 0 }
        let candidates = used.isEmpty ? Array(recipes.values) : used

        return Array(candidates.sorted { left, right in
            let leftUses = uses[left.id, default: 0]
            let rightUses = uses[right.id, default: 0]
            if leftUses != rightUses { return leftUses > rightUses }
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id.uuidString < right.id.uuidString
        }.prefix(limit))
    }

    /// Counted from the projected log so a deleted meal immediately stops
    /// contributing to a dish's popularity.
    public func timesLogged(recipeID: UUID) -> Int {
        meals.values.count { $0.recipeID == recipeID }
    }

    public func meals(from start: EpochMillis, to end: EpochMillis) -> [MealEntry] {
        meals.values.filter { $0.eatenAt >= start && $0.eatenAt < end }
            .sorted { $0.eatenAt < $1.eatenAt }
    }

    public func sets(from start: EpochMillis, to end: EpochMillis) -> [SetRecord] {
        sets.filter { $0.finishedAt >= start && $0.finishedAt < end }
            .sorted { $0.finishedAt < $1.finishedAt }
    }
}
