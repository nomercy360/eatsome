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

    func completeSet(_ record: SetRecord) async {
        await self.record(.setCompleted(record), occurredAt: record.finishedAt)
        await HealthKitBridge.shared.save(record, config: config)
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

    func setsToday(calendar: Calendar = .current) -> [SetRecord] {
        let start = calendar.startOfDay(for: Date()).epochMillis
        return projection.sets(from: start, to: start + 86_400_000)
    }

    var movedToday: Bool { !setsToday().isEmpty }

    /// Consecutive days ending today with at least one set.
    func movementStreak(calendar: Calendar = .current) -> Int {
        let days = Set(projection.sets.map {
            calendar.startOfDay(for: Date(epochMillis: $0.finishedAt))
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
