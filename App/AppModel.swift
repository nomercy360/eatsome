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

    var hasAPIKey: Bool { (try? keychain.get(.openAIAPIKey))??.isEmpty == false }

    private let keychain = KeychainStore()
    private var log: EventLog?
    private var recognizer: (any MealRecognizer)?

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

    func deleteMeal(_ meal: MealEntry) async {
        await record(.mealDeleted(mealID: meal.id), occurredAt: meal.eatenAt)
    }

    func updateHabits(_ habits: DietHabits) async {
        await record(.habitsUpdated(habits))
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

    func recognize(imageData: Data) async throws -> MealRecognition {
        guard let recognizer else { throw MealRecognizerError.missingAPIKey }
        return try await recognizer.recognize(imageData: imageData, mimeType: "image/jpeg")
    }

    func setAPIKey(_ key: String?) {
        try? keychain.set(key, for: .openAIAPIKey)
        rebuildRecognizer()
    }

    private func rebuildRecognizer() {
        let keychain = self.keychain
        let luna = LunaSession(configuration: config.lunaConfiguration) {
            try keychain.get(.openAIAPIKey)
        }
        guard let directory = (try? EventLog.defaultURL())?
            .deletingLastPathComponent()
            .appendingPathComponent("recognitions", isDirectory: true),
            let caching = try? CachingRecognizer(upstream: luna, directory: directory)
        else {
            recognizer = luna
            return
        }
        recognizer = caching
    }
}
