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

    /// Where each message in the thread has got to.
    ///
    /// Deliberately not persisted — see `LogMessageState`. Anything in flight
    /// when the app was killed comes back as `sent`, which is the truth: it was
    /// written down and it has not been read yet. `resumeUnreadMessages()` picks
    /// those up on launch, so a message can never be stranded by a crash.
    private(set) var messageStates: [UUID: LogMessageState] = [:]

    /// Which vendor recognizes photos on this device. Stored here rather than in
    /// the config file because it is a per-device experiment, not a policy: the
    /// point is to run both against your own plates and keep the better one.
    ///
    /// Gemini is the one that was kept. Note this value is sent with every
    /// request and overrides the Worker's own default, so changing production
    /// means changing both — a deployment that disagrees with the build loses
    /// to the build, silently.
    private(set) var provider: RecognitionProvider = .gemini

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
        resumeUnreadMessages()
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
                throw BackendError.invalidRequest("This build has no backend access, so there is nothing stored to delete.")
            }
            try await backend.deleteAccountData()
            hasAcceptedPhotoProcessing = false
            UserDefaults.standard.removeObject(forKey: "photoProcessingConsentVersion")
        } catch {
            cloudError = error.localizedDescription
        }
    }

    // MARK: - The thread
    //
    // Messages are a queue, not a form. Each one is written down the instant it
    // is sent, then read independently and in parallel; order of completion does
    // not matter, and nothing about the composer waits on any of it. A retry
    // re-sends the message that already exists rather than asking anyone to type
    // it again — which is the whole reason the message is a stored event and the
    // meal is a separate one.

    /// Today's thread, oldest first.
    var thread: [ThreadTurn] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date()).epochMillis
        return projection.thread(from: start, to: start + 86_400_000)
    }

    func state(of message: LogMessage) -> LogMessageState {
        if let known = messageStates[message.id] { return known }
        // A meal already references it: this is a message from a previous
        // session whose reading finished before the app was closed.
        if let meal = projection.meal(forMessage: message.id) { return .logged(mealID: meal.id) }
        return .sent
    }

    var isReadingAnything: Bool {
        messageStates.values.contains { if case .reading = $0 { return true } else { return false } }
    }

    /// Write the message down, then read it. In that order, always: the log
    /// entry is what makes the thread survive being offline, being killed, or
    /// the reading failing.
    func send(said: String?, photo: Data? = nil) async {
        let normalized = photo.flatMap(ModelInputImage.render)
        let text = said?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = LogMessage(
            said: (text?.isEmpty ?? true) ? nil : text,
            photoHash: normalized.flatMap { PhotoStore.shared.store($0) }
        )
        guard !message.isEmpty else { return }

        await record(.messageSent(message), occurredAt: message.sentAt)
        read(message, bytes: normalized)
    }

    /// Log a repeat dish straight from a chip, with no model call.
    ///
    /// The ingredients and their weights are already known from the last time it
    /// was logged, and asking a model to describe lentil soup again would spend
    /// money to be told the same thing less reliably. It still goes through a
    /// message, so the thread reads the same as any other entry.
    func send(dish entry: DishLibrary.Entry) async {
        let message = LogMessage(said: entry.name)
        await record(.messageSent(message), occurredAt: message.sentAt)
        let meal = entry.newMeal(
            eatenAt: SpokenTime.eatenAt(in: entry.name, sentAt: message.sentAt),
            messageID: message.id
        )
        await logMeal(meal)
        messageStates[message.id] = .logged(mealID: meal.id)
    }

    /// The same send, for a day that is not today.
    ///
    /// Reached from the day sheet of an earlier day — the one thing a gap in the
    /// log is still good for. The message is stamped on that day so the thread
    /// keeps its own chronology, and a time named in the sentence still wins:
    /// "9 pm" on Monday's sheet means Monday at nine.
    func send(said: String, on day: Date, calendar: Calendar = .current) async {
        let text = said.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Noon, so a message with no time in it lands inside the day it is
        // being added to rather than at whatever hour it happens to be now.
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
        let message = LogMessage(sentAt: noon.epochMillis, said: text)
        await record(.messageSent(message), occurredAt: message.sentAt)
        read(message, bytes: nil)
    }

    func retry(_ message: LogMessage) {
        read(message, bytes: PhotoStore.shared.data(for: message.photoHash))
    }

    /// Anything written down but never read — the app was killed mid-flight, or
    /// the send happened offline. Picked up on launch so a message cannot be
    /// stranded by something that was not the person's doing.
    private func resumeUnreadMessages() {
        for message in projection.messages.values
        where projection.meal(forMessage: message.id) == nil && messageStates[message.id] == nil {
            read(message, bytes: PhotoStore.shared.data(for: message.photoHash))
        }
    }

    private func read(_ message: LogMessage, bytes: Data?) {
        if case .reading = messageStates[message.id] { return }
        messageStates[message.id] = .reading
        Task { await readNow(message, bytes: bytes) }
    }

    private func readNow(_ message: LogMessage, bytes: Data?) async {
        do {
            let artifact = try await recognize(
                MealMessage(said: message.said, imageData: bytes)
            )
            let dishes = artifact.recognition.asMealDishes() ?? []
            let items = dishes.isEmpty
                ? artifact.recognition.asMealItems()
                : dishes.flatMap { $0.flattened() }

            let meal = MealEntry(
                // The sentence may say when: "half a kebab at 2 am". Read in
                // code rather than asked of the model — see `SpokenTime`.
                eatenAt: SpokenTime.eatenAt(in: message.said, sentAt: message.sentAt),
                items: items,
                // A photo with a caption is still a photograph: the picture is
                // the stronger evidence and the words are what it could not show.
                source: bytes == nil ? .text : .photo,
                photoHash: message.photoHash,
                note: message.trimmedText,
                recognitionEvidence: MealRecognitionEvidence(
                    promptVersion: artifact.promptVersion,
                    rawModelJSON: artifact.rawModelJSON,
                    initialItems: artifact.recognition.asMealItems(),
                    otherMealsVisible: artifact.recognition.otherMealsVisible
                ),
                storedDishes: dishes.isEmpty ? nil : dishes,
                messageID: message.id
            )
            await logMeal(meal)
            messageStates[message.id] = .logged(mealID: meal.id)
        } catch {
            messageStates[message.id] = .failed(reason: error.localizedDescription)
        }
    }

    /// Answering the one question a card ever asks, in words.
    ///
    /// The same delta a fix is, applied straight to the saved meal — the meal
    /// was never blocked on the answer, it was saved with the model's best guess
    /// and marked as corrected once you touched it. Both representations are
    /// rewritten together so the flat list and the dishes cannot disagree.
    func refineMeal(_ meal: MealEntry, note: String) async {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            let revision = try await refine(
                imageData: PhotoStore.shared.data(for: meal.photoHash),
                current: meal.items,
                note: text
            )
            var revised = meal
            revised.items = revision.applied(to: meal.items)
            if let dishes = meal.storedDishes {
                let regrouped = MealDish.regrouped(revised.items, keeping: dishes)
                revised.storedDishes = regrouped
                revised.items = regrouped.flatMap { $0.flattened() }
            }
            revised.note = text
            await reviseMeal(revised)
        } catch {
            cloudError = error.localizedDescription
        }
    }

    /// Removing a meal takes its bubble with it, so the thread never shows a
    /// message with nothing under it and no way to get one.
    func deleteTurn(_ turn: ThreadTurn) async {
        if let meal = turn.meal { await deleteMeal(meal) }
        if let message = turn.message {
            messageStates.removeValue(forKey: message.id)
            await record(.messageDeleted(messageID: message.id), occurredAt: message.sentAt)
        }
    }

    /// The chips above the keyboard: what you are most likely about to type,
    /// for this time of day, narrowed by what you have typed so far.
    func dishSuggestions(typed: String = "", limit: Int = 3) -> [DishLibrary.Entry] {
        DishLibrary.suggestions(in: projection.meals.values, typed: typed, limit: limit)
    }

    // MARK: - Olives

    func olives(for meal: MealEntry) -> OliveRating {
        OliveRating.forMeal(meal, configuration: config.oliveConfiguration)
    }

    /// The day so far, portion-weighted. Nil on a day with nothing logged —
    /// which the pinned strip must draw differently from a three-olive day.
    func olives(on day: Date = Date(), calendar: Calendar = .current) -> OliveRating? {
        OliveRating.forDay(meals(on: day, calendar: calendar), configuration: config.oliveConfiguration)
    }

    // MARK: - Dishes
    //
    // `Recipe` and its two events are still decoded and replayed — the log is
    // append-only and a build that could not read a `recipe_saved` line would
    // drop it — but nothing writes one any more. Curating a list of dishes by
    // hand was a job the log can do by itself: what you repeat, and how it came
    // out the last time you corrected it, is already written down. See
    // `DishLibrary`.

    /// How many distinct dishes the log has seen, for the Workshop counters.
    var knownDishCount: Int {
        DishLibrary.entries(in: projection.meals.values).count
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

    // MARK: - Nutrition

    /// Per device, like the recognition provider: this is a training decision,
    /// not a property of the food.
    var proteinIntent: Protein.Intent = .active {
        didSet { UserDefaults.standard.set(proteinIntent.rawValue, forKey: Self.proteinIntentKey) }
    }

    private static let proteinIntentKey = "proteinIntent"

    /// Everything today came to, with the share of the weight that answered.
    ///
    /// One computation for all five figures, so nothing on any screen can
    /// disagree with anything on another about the same day.
    var nutrientsToday: NutrientTotal {
        nutrients(in: mealsToday())
    }

    func nutrients(in meals: [MealEntry]) -> NutrientTotal {
        Nutrition.total(in: meals, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    func nutrients(in meal: MealEntry) -> NutrientTotal {
        Nutrition.total(in: meal, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    func nutrients(in dishes: [MealDish]) -> NutrientTotal {
        Nutrition.total(in: dishes, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    func nutrients(in dish: MealDish) -> NutrientTotal {
        Nutrition.total(in: dish, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    var proteinToday: Double { nutrientsToday.nutrients.protein }

    /// What a described dish contributes, for the dishes screen. No share
    /// factor: a recipe is one serving of itself, and how much of it you ate is
    /// a property of the meal you log, not of the dish.
    func protein(in items: [MealItem]) -> Double {
        Protein.grams(in: items, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    /// What one dish contributes at its own quantity — the figure the dish
    /// sheet shows while the count stepper is being turned. On a meal old
    /// enough to be described in portions the ingredients alone are one normal
    /// serving of it, so anything reading them directly reports a large plate
    /// as a normal one.
    func protein(in dish: MealDish) -> Double {
        Protein.grams(in: dish, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    /// What a meal being composed is worth, before it is saved. The flat rows
    /// cannot answer this: they carry no panel, so a labelled drink would be
    /// worth its food group here and its label afterwards.
    func protein(in dishes: [MealDish]) -> Double {
        Protein.grams(in: dishes, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    /// The one figure above a plate — protein, or the caffeine a label printed
    /// when there is no protein to report. See `PlateFigure`.
    func figure(for dishes: [MealDish], share: MealShare = .whole) -> PlateFigure {
        PlateFigure.forPlate(dishes, share: share, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    func figure(for meal: MealEntry) -> PlateFigure {
        PlateFigure.forMeal(meal, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    /// What one saved meal contributed, share included — half a plate is half
    /// the protein, and that is the number the day was built from.
    func protein(in meal: MealEntry) -> Double {
        Protein.grams(in: meal, gramsPerServing: config.proteinTable, foods: config.nutrientsPerGram)
    }

    /// Nil until Health has a weight: a target invented from a guessed body
    /// weight would be a number with no meaning behind it.
    var proteinTarget: Double? { dailyTargets?.protein }

    /// All five, from the same body weight and the same intent. Nil for the same
    /// reason `proteinTarget` is: without a weight there is nothing to derive
    /// them from, and a default figure would be a stranger's target wearing this
    /// person's label.
    var dailyTargets: DailyTargets? {
        latestWeight.map { DailyTargets.forBody(weightKilograms: $0.kilograms, intent: proteinIntent) }
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

    /// Consent is required for anything that leaves the phone, not only for a
    /// photograph.
    ///
    /// When logging was photo-first those were the same thing. They are not any
    /// more: a typed meal goes to the same third-party provider, and gating only
    /// the picture would mean the first thing a new user sends leaves the device
    /// without ever having been mentioned. `SendConsentView` says both.
    func recognize(_ message: MealMessage) async throws -> RecognitionArtifact {
        guard hasAcceptedPhotoProcessing else {
            throw BackendError.invalidRequest("Agree before a meal is sent to be read.")
        }
        guard !message.isEmpty else { throw MealRecognizerError.emptyMessage }
        guard let recognizer else { throw MealRecognizerError.missingAPIKey }
        return try await recognizer.recognize(message)
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

    /// Where live dictation gets its short-lived key. Nil on a build with no
    /// backend, which greys the mic rather than letting it fail after the tap.
    var voiceKeySource: (any VoiceKeySource)? {
        backend.map(BackendVoiceKeys.init(backend:))
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
