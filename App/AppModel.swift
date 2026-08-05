import Foundation
import Observation
import ShamanCore

@MainActor
@Observable
final class AppModel {
    private(set) var config: AppConfig = .fallback
    private(set) var configSource: ConfigLoader.Source = .fallback
    private(set) var projection = Projection()
    private(set) var loadError: String?
    private(set) var healthSnapshot = HealthSnapshot.empty
    private(set) var healthError: String?
    private(set) var isLoadingHealth = false
    private(set) var healthLastRefreshedAt: Date?
    private(set) var hasRequestedHealthAccess = UserDefaults.standard.bool(forKey: "hasRequestedHealthAccess")
    /// Surfaced in Settings. A silently skipped line is how you lose trust in
    /// your own data six months later.
    private(set) var skippedLogLines = 0

    /// Which vendor recognizes photos on this device. Stored here rather than in
    /// the config file because it is a per-device experiment, not a policy: the
    /// point is to run both against your own plates and keep the better one.
    private(set) var provider: RecognitionProvider = .openAI

    var hasAPIKey: Bool { hasKey(for: provider) }

    func hasKey(for provider: RecognitionProvider) -> Bool {
        (try? keychain.get(provider.keychainKey))??.isEmpty == false
    }

    var activeModel: String { config.model(for: provider) }

    private static let providerDefaultsKey = "recognitionProvider"
    private let keychain = KeychainStore()
    private var log: EventLog?
    private var recognizer: (any MealRecognizer)?
    private var refiner: (any MealRefiner)?

    /// Point this at a JSON file in a bucket to retune thresholds and the
    /// recognition prompt without a TestFlight round trip. nil until you have
    /// somewhere to host it — the bundled copy is used meanwhile.
    private let configURL: URL? = nil

    func bootstrap() async {
        do {
            let log = try EventLog(url: try EventLog.defaultURL())
            self.log = log
            let (events, skipped) = try await log.load()
            projection = Projection(replaying: events)
            skippedLogLines = skipped
        } catch {
            loadError = error.localizedDescription
        }

        let cache = (try? EventLog.defaultURL())?
            .deletingLastPathComponent()
            .appendingPathComponent("config.json")
        if let cache {
            (config, configSource) = await ConfigLoader(remoteURL: configURL, cacheURL: cache).load()
        }

        provider = UserDefaults.standard.string(forKey: Self.providerDefaultsKey)
            .flatMap(RecognitionProvider.init(rawValue:))
            ?? config.defaultProvider

        rebuildRecognizer()
        await refreshHealth()
    }

    // MARK: - Writes

    func record(_ payload: EventPayload, occurredAt: EpochMillis = Date().epochMillis) async {
        let event = LoggedEvent(occurredAt: occurredAt, payload: payload)
        projection.apply(event)
        do {
            try await log?.append(event)
        } catch {
            loadError = "Could not write to the log: \(error.localizedDescription)"
        }
    }

    func logMeal(_ meal: MealEntry) async {
        await record(.mealLogged(meal), occurredAt: meal.eatenAt)
    }

    func reviseMeal(_ meal: MealEntry) async {
        var revised = meal
        revised.wasCorrected = true
        await record(.mealRevised(revised), occurredAt: revised.eatenAt)
    }

    /// The event log keeps the deletion; the photograph does not get to outlive
    /// the meal it belonged to.
    func deleteMeal(_ meal: MealEntry) async {
        PhotoStore.shared.remove(meal.photoHash)
        await record(.mealDeleted(mealID: meal.id), occurredAt: meal.eatenAt)
    }

    func updateHabits(_ habits: DietHabits) async {
        await record(.habitsUpdated(habits))
    }

    // MARK: - Recipes

    var recipes: [Recipe] { projection.recentRecipes }

    func saveRecipe(_ recipe: Recipe) async {
        var stamped = recipe
        stamped.updatedAt = Date().epochMillis
        await record(.recipeSaved(stamped))
    }

    func deleteRecipe(_ recipe: Recipe) async {
        await record(.recipeDeleted(recipeID: recipe.id))
    }

    /// Logging a recipe also bumps it to the top of the list: what you cooked
    /// today is what you are most likely to cook again.
    func logRecipe(_ recipe: Recipe, at date: Date, share: MealShare) async {
        await logMeal(recipe.newMeal(eatenAt: date.epochMillis, share: share))
        await saveRecipe(recipe)
    }

    // MARK: - Reads

    func adherence(endingAt end: Date = Date(), calendar: Calendar = .current) -> MedasResult {
        // The window ends at the start of tomorrow so today counts in full.
        let end = calendar.startOfDay(for: end).addingTimeInterval(86_400).epochMillis
        let start = end - EpochMillis(config.medas.windowDays) * 86_400_000
        return MedasScorer(configuration: config.medas).score(
            meals: projection.meals(from: start, to: end),
            habits: projection.habits,
            windowEnd: end,
            calendar: calendar
        )
    }

    func mealsToday(calendar: Calendar = .current) -> [MealEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: Date()) else { return [] }
        return projection.meals.values
            .filter { interval.contains(Date(epochMillis: $0.eatenAt)) }
            .sorted { $0.eatenAt > $1.eatenAt }
    }

    func workoutsToday(calendar: Calendar = .current) -> [ImportedWorkout] {
        guard let interval = calendar.dateInterval(of: .day, for: Date()) else { return [] }
        return healthSnapshot.workouts.filter { interval.contains($0.startedAt) }
    }

    var movedToday: Bool { !workoutsToday().isEmpty }

    /// Consecutive days ending today with at least one set.
    func movementStreak(calendar: Calendar = .current) -> Int {
        let days = Set(healthSnapshot.workouts.map {
            calendar.startOfDay(for: $0.startedAt)
        })
        var streak = 0
        var day = calendar.startOfDay(for: Date())
        // Today not being done yet should not read as a broken streak.
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    var latestSleep: SleepSummary? { healthSnapshot.sleep.first }
    var latestWeight: WeightMeasurement? { healthSnapshot.weights.first }

    /// True when Health returned nothing at all. Read denial is by design
    /// indistinguishable from an empty store, so the UI must say both rather
    /// than pick one and be wrong half the time.
    var healthIsEmpty: Bool {
        healthSnapshot.workouts.isEmpty
            && healthSnapshot.sleep.isEmpty
            && healthSnapshot.weights.isEmpty
    }

    // MARK: - How today compares
    //
    // Each metric gets its own baseline, because one formula across three of
    // them would be wrong for at least two: a weight is a step from the last
    // reading, a night's sleep only means something against your own average,
    // and workouts are a weekly count.

    /// Last measurement minus the one before it, in kilograms.
    var weightDelta: Double? {
        let sorted = healthSnapshot.weights.sorted { $0.measuredAt > $1.measuredAt }
        guard sorted.count >= 2 else { return nil }
        return sorted[0].kilograms - sorted[1].kilograms
    }

    /// Last night against the average of the nights before it.
    var sleepDeltaAgainstAverage: TimeInterval? {
        let nights = healthSnapshot.sleep.sorted { $0.startedAt > $1.startedAt }
        guard let latest = nights.first else { return nil }
        let baseline = nights.dropFirst().prefix(7)
        guard !baseline.isEmpty else { return nil }
        return latest.asleep - baseline.reduce(0) { $0 + $1.asleep } / Double(baseline.count)
    }

    func workoutCount(weeksAgo: Int, calendar: Calendar = .current) -> Int {
        let end = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: Date()) ?? Date()
        let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
        return healthSnapshot.workouts.count { $0.startedAt >= start && $0.startedAt < end }
    }

    func weightChange(overDays days: Int, calendar: Calendar = .current) -> Double? {
        guard let latestWeight else { return nil }
        let target = calendar.date(byAdding: .day, value: -days, to: latestWeight.measuredAt)
            ?? latestWeight.measuredAt.addingTimeInterval(-Double(days) * 86_400)
        let tolerance = Double(max(2, days / 3)) * 86_400
        guard let baseline = healthSnapshot.weights
            .dropFirst()
            .min(by: {
                abs($0.measuredAt.timeIntervalSince(target)) < abs($1.measuredAt.timeIntervalSince(target))
            }),
            abs(baseline.measuredAt.timeIntervalSince(target)) <= tolerance
        else { return nil }
        return latestWeight.kilograms - baseline.kilograms
    }

    // MARK: - HealthKit

    func connectHealth() async {
        healthError = nil
        do {
            try await HealthKitBridge.shared.requestAuthorization()
            hasRequestedHealthAccess = true
            UserDefaults.standard.set(true, forKey: "hasRequestedHealthAccess")
            await refreshHealth()
        } catch {
            healthError = error.localizedDescription
        }
    }

    func refreshHealth() async {
        guard hasRequestedHealthAccess else {
            healthSnapshot = .empty
            healthError = nil
            return
        }
        guard !isLoadingHealth else { return }
        isLoadingHealth = true
        healthError = nil
        defer { isLoadingHealth = false }
        do {
            healthSnapshot = try await HealthKitBridge.shared.loadSnapshot()
            healthLastRefreshedAt = Date()
        } catch {
            healthError = error.localizedDescription
        }
    }

    // MARK: - Recognition

    func recognize(imageData: Data, note: String?) async throws -> RecognitionArtifact {
        guard let recognizer else { throw MealRecognizerError.missingAPIKey }
        return try await recognizer.recognize(imageData: imageData, mimeType: "image/jpeg", note: note)
    }

    /// Not cached: a correction is a one-off, and its answer depends on a list
    /// that only exists in the sheet you are looking at.
    func refine(imageData: Data?, current: [MealItem], note: String) async throws -> MealRevision {
        guard let refiner else { throw MealRecognizerError.missingAPIKey }
        return try await refiner.refine(
            imageData: imageData,
            mimeType: "image/jpeg",
            current: current,
            note: note
        )
    }

    func setAPIKey(_ key: String?, for provider: RecognitionProvider? = nil) {
        try? keychain.set(key, for: (provider ?? self.provider).keychainKey)
        rebuildRecognizer()
    }

    func setProvider(_ provider: RecognitionProvider) {
        guard provider != self.provider else { return }
        self.provider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerDefaultsKey)
        rebuildRecognizer()
    }

    private func rebuildRecognizer() {
        let keychain = self.keychain
        let key = provider.keychainKey
        let upstream: any MealRecognizer
        let promptVersion: String
        switch provider {
        case .openAI:
            let configuration = config.lunaConfiguration
            promptVersion = configuration.promptVersion
            upstream = LunaSession(configuration: configuration) { try keychain.get(key) }
        case .gemini:
            let configuration = config.geminiConfiguration
            promptVersion = configuration.promptVersion
            upstream = GeminiSession(configuration: configuration) { try keychain.get(key) }
        }

        refiner = upstream as? any MealRefiner

        guard let directory = (try? EventLog.defaultURL())?
            .deletingLastPathComponent()
            .appendingPathComponent("recognitions", isDirectory: true),
            // Namespaced by generator: the same plate re-read by the other
            // provider must cost an API call, or the comparison is fiction.
            let caching = try? CachingRecognizer(
                upstream: upstream,
                directory: directory,
                namespace: promptVersion
            )
        else {
            recognizer = upstream
            return
        }
        recognizer = caching
    }
}
