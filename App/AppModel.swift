import Foundation
import Observation
import ShamanCore

private let photoProcessingConsentVersion = "photo-processing-2026-08-06-v1"

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
    /// Set once the four intro screens have been seen or skipped. Not an event:
    /// it is a fact about this install, not about what was eaten, and the log is
    /// for the latter.
    private(set) var hasOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    /// Surfaced in Settings. A silently skipped line is how you lose trust in
    /// your own data six months later.
    private(set) var skippedLogLines = 0
    private(set) var cloudError: String?
    private(set) var isDeletingCloudData = false
    private(set) var hasAcceptedPhotoProcessing =
        UserDefaults.standard.string(forKey: "photoProcessingConsentVersion") == photoProcessingConsentVersion

    /// Which vendor recognizes photos on this device. Stored here rather than in
    /// the config file because it is a per-device experiment, not a policy: the
    /// point is to run both against your own plates and keep the better one.
    private(set) var provider: RecognitionProvider = .openAI

    var hasBackendAccess: Bool { backendToken != nil }

    var activeModel: String { config.model(for: provider) }

    private static let providerDefaultsKey = "recognitionProvider"
    private static let onboardedKey = "hasCompletedOnboarding"
    private let keychain = KeychainStore()
    private var log: EventLog?
    private var loadedEvents: [LoggedEvent] = []
    private var recognizer: (any MealRecognizer)?
    private var refiner: (any MealRefiner)?
    private var backend: BackendSession?

    /// Point this at a JSON file in a bucket to retune thresholds and the
    /// recognition prompt without a TestFlight round trip. nil until you have
    /// somewhere to host it — the bundled copy is used meanwhile.
    private let configURL: URL? = nil

    func bootstrap() async {
        do {
            let log = try EventLog(url: try EventLog.defaultURL())
            self.log = log
            let (events, skipped) = try await log.load()
            loadedEvents = events
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
        proteinIntent = UserDefaults.standard.string(forKey: Self.proteinIntentKey)
            .flatMap(Protein.Intent.init(rawValue:))
            ?? .active

        rebuildRecognizer()
        if hasAcceptedPhotoProcessing { syncMealEvents(loadedEvents) }
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
        loadedEvents.append(event)
        syncMealEvents([event])
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

    func completeOnboarding() {
        hasOnboarded = true
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
    }

    func acceptPhotoProcessing() {
        hasAcceptedPhotoProcessing = true
        UserDefaults.standard.set(photoProcessingConsentVersion, forKey: "photoProcessingConsentVersion")
        syncMealEvents(loadedEvents)
    }

    func revokePhotoProcessingAndDeleteCloudData() async {
        guard !isDeletingCloudData else { return }
        isDeletingCloudData = true
        cloudError = nil
        defer { isDeletingCloudData = false }
        do {
            guard let backend else {
                throw BackendError.invalidRequest("Save your development invite before deleting its cloud data.")
            }
            try await backend.deleteAccountData()
            hasAcceptedPhotoProcessing = false
            UserDefaults.standard.removeObject(forKey: "photoProcessingConsentVersion")
        } catch {
            cloudError = error.localizedDescription
        }
    }

    // MARK: - Recipes

    var recipes: [Recipe] { projection.recentRecipes }

    /// Counted from the log rather than kept as a tally, so deleting a meal
    /// takes its use with it.
    func timesLogged(_ recipe: Recipe) -> Int {
        projection.meals.values.count { $0.recipeID == recipe.id }
    }

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
        meals(on: Date(), calendar: calendar)
    }

    /// Newest first, which is the order a day reads in when you are looking for
    /// the meal you just logged.
    func meals(on day: Date, calendar: Calendar = .current) -> [MealEntry] {
        guard let interval = calendar.dateInterval(of: .day, for: day) else { return [] }
        return projection.meals.values
            .filter { interval.contains(Date(epochMillis: $0.eatenAt)) }
            .sorted { $0.eatenAt > $1.eatenAt }
    }

    /// The seven dots, over the same window and the same boundary the scorer
    /// uses — the row and the score must never describe different weeks.
    func weekDays(endingAt end: Date = Date(), calendar: Calendar = .current) -> [DayLog] {
        let windowEnd = calendar.startOfDay(for: end).addingTimeInterval(86_400).epochMillis
        let windowStart = windowEnd - EpochMillis(config.medas.windowDays) * 86_400_000
        return WeekRhythm.days(
            meals: projection.meals(from: windowStart, to: windowEnd),
            endingAt: windowEnd,
            days: config.medas.windowDays,
            calendar: calendar
        )
    }

    /// Consecutive days back from today, newest first — what the history screen
    /// lists, gaps included.
    func recentDays(_ count: Int, endingAt end: Date = Date(), calendar: Calendar = .current) -> [DayLog] {
        let windowEnd = calendar.startOfDay(for: end).addingTimeInterval(86_400).epochMillis
        let windowStart = windowEnd - EpochMillis(count) * 86_400_000
        return WeekRhythm.days(
            meals: projection.meals(from: windowStart, to: windowEnd),
            endingAt: windowEnd,
            days: count,
            calendar: calendar
        )
        .reversed()
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

    // MARK: - Protein

    /// Per device, like the recognition provider: this is a training decision,
    /// not a property of the food.
    var proteinIntent: Protein.Intent = .active {
        didSet { UserDefaults.standard.set(proteinIntent.rawValue, forKey: Self.proteinIntentKey) }
    }

    private static let proteinIntentKey = "proteinIntent"

    var proteinToday: Double {
        Protein.grams(in: mealsToday(), gramsPerServing: config.proteinTable)
    }

    /// Nil until Health has a weight: a target invented from a guessed body
    /// weight would be a number with no meaning behind it.
    var proteinTarget: Double? {
        latestWeight.map { Protein.dailyTarget(weightKilograms: $0.kilograms, intent: proteinIntent) }
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
        guard hasAcceptedPhotoProcessing else {
            throw BackendError.invalidRequest("Agree to photo processing before sending a meal photo.")
        }
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

    func setBackendToken(_ token: String?) {
        try? keychain.set(token, for: .backendAPIToken)
        rebuildRecognizer()
        if token?.isEmpty == false, hasAcceptedPhotoProcessing { syncMealEvents(loadedEvents) }
    }

    func setProvider(_ provider: RecognitionProvider) {
        guard provider != self.provider else { return }
        self.provider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.providerDefaultsKey)
        rebuildRecognizer()
    }

    private func rebuildRecognizer() {
        guard let baseURL = backendBaseURL,
              let token = backendToken,
              let deviceID = stableDeviceID()
        else {
            backend = nil
            recognizer = nil
            refiner = nil
            return
        }
        let session = BackendSession(configuration: .init(
            baseURL: baseURL,
            token: token,
            deviceID: deviceID,
            provider: provider
        ))
        backend = session
        recognizer = session
        refiner = session
    }

    private var backendBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "EatsomeAPIBaseURL") as? String,
              !value.isEmpty
        else { return nil }
        return URL(string: value)
    }

    private var backendToken: String? {
        if let saved = (try? keychain.get(.backendAPIToken)) ?? nil, !saved.isEmpty { return saved }
        guard let bundled = Bundle.main.object(forInfoDictionaryKey: "EatsomeAPIToken") as? String,
              !bundled.isEmpty,
              !bundled.contains("$(")
        else { return nil }
        return bundled
    }

    private func stableDeviceID() -> String? {
        if let saved = (try? keychain.get(.deviceID)) ?? nil, !saved.isEmpty { return saved }
        let created = UUIDv7.generate().uuidString
        do {
            try keychain.set(created, for: .deviceID)
            return created
        } catch {
            cloudError = error.localizedDescription
            return nil
        }
    }

    private func syncMealEvents(_ events: [LoggedEvent]) {
        guard hasAcceptedPhotoProcessing, let backend, !events.isEmpty else { return }
        Task {
            do {
                try await backend.syncMealEvents(events)
                cloudError = nil
            } catch {
                cloudError = "Cloud sync: \(error.localizedDescription)"
            }
        }
    }
}
