import Foundation
import Observation
import ShamanCore

private let photoProcessingConsentVersion = "photo-processing-2026-08-06-v1"
/// Bump this only when onboarding gains required data that an existing install
/// cannot safely infer. The old boolean is still written for downgrade
/// compatibility, but it no longer lets an upgraded install skip new required
/// questions forever.
private let onboardingVersion = "nutrition-profile-2026-08-11-v2"

@MainActor
@Observable
final class AppModel {
    enum NutritionProfileField: String, CaseIterable {
        case age
        case referenceSex
        case height
        case weight
        case bodyFat
        case activity
    }

    private(set) var config: AppConfig = .fallback
    private(set) var configSource: ConfigLoader.Source = .fallback
    private(set) var projection = Projection()
    private(set) var loadError: String?
    private(set) var healthSnapshot = HealthSnapshot.empty
    private(set) var healthError: String?
    private(set) var isLoadingHealth = false
    private(set) var healthLastRefreshedAt: Date?
    private(set) var hasRequestedHealthAccess = UserDefaults.standard.bool(forKey: "hasRequestedHealthAccess")
    private(set) var manualNutritionProfile = NutritionProfile()
    private(set) var nutritionProfileHealthOverrides: Set<NutritionProfileField> = Set(
        UserDefaults.standard
            .stringArray(forKey: "nutritionProfile.healthOverrides.v1")?
            .compactMap(NutritionProfileField.init(rawValue:))
            ?? []
    )
    /// True only after this install has completed the current required setup.
    /// Versioning is intentional: users who finished an older, smaller flow
    /// must see newly required profile questions once after upgrading.
    private(set) var hasOnboarded =
        UserDefaults.standard.string(forKey: "completedOnboardingVersion") == onboardingVersion
    /// Surfaced in Settings. A silently skipped line is how you lose trust in
    /// your own data six months later.
    private(set) var skippedLogLines = 0
    private(set) var cloudError: String?
    private(set) var isDeletingCloudData = false
    private(set) var hasAcceptedPhotoProcessing =
        UserDefaults.standard.string(forKey: "photoProcessingConsentVersion") == photoProcessingConsentVersion
    /// RootView waits for this before deciding whether to show identity,
    /// onboarding, or the thread. Without it an existing valid Keychain session
    /// flashes the sign-in wall while launch is still reading credentials.
    private(set) var hasBootstrapped = false
    /// Production is account-only. The bundled bearer credential identifies an
    /// app build; a Keychain session plus its account id identifies the person.
    private(set) var isSignedIn = false
    private(set) var signedInAccountID =
        UserDefaults.standard.string(forKey: "signedInAccountID")

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

    var hasBackendAccess: Bool { backendBaseURL != nil && backendToken != nil }

    var activeModel: String { config.model(for: provider) }

    private static let providerDefaultsKey = "recognitionProvider"
    /// Not a secret and not proof of anything — it is shown in the workshop so
    /// two devices can be seen landing on the same account. The session token
    /// that actually proves it lives in the Keychain.
    private static let accountIDDefaultsKey = "signedInAccountID"
    private static let onboardedKey = "hasCompletedOnboarding"
    private static let onboardingVersionKey = "completedOnboardingVersion"
    private static let tableVisibilityOverridesKey = "tableVisibilityOverrides.v1"
    private let keychain = KeychainStore()
    private var log: EventLog?
    private var loadedEvents: [LoggedEvent] = []
    private var recognizer: (any MealRecognizer)?
    private var refiner: (any MealRefiner)?
    private var backend: BackendSession?
    private var hasSessionToken = false
    private var isSynchronizingAccount = false
    /// Only messages written on this install may be resumed. Pulling an unread
    /// bubble from another phone must not run recognition twice and create a
    /// second meal for the same sentence.
    private var locallyRecordedMessageIDs: Set<UUID> = []

    /// Point this at a JSON file in a bucket to retune thresholds and the
    /// recognition prompt without a TestFlight round trip. nil until you have
    /// somewhere to host it — the bundled copy is used meanwhile.
    private let configURL: URL? = nil

    func bootstrap() async {
        defer { hasBootstrapped = true }
        do {
            let log = try EventLog(url: try EventLog.defaultURL())
            self.log = log
            let (events, skipped) = try await log.load()
            loadedEvents = events
            locallyRecordedMessageIDs = Set(events.compactMap { event in
                guard event.sourceDeviceId == nil else { return nil }
                if case .messageSent(let message) = event.payload { return message.id }
                return nil
            })
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
        if let data = UserDefaults.standard.data(forKey: Self.nutritionProfileKey),
           let saved = try? JSONDecoder().decode(NutritionProfile.self, from: data) {
            manualNutritionProfile = saved
        } else if UserDefaults.standard.string(forKey: "proteinIntent") == "building" {
            // The old three-way protein switch was local-only. Carry its one
            // unambiguous choice forward without inventing the missing body data.
            manualNutritionProfile.goal = .gainMuscle
        }
        hasSessionToken = ((try? keychain.get(.sessionToken)) ?? nil)?.isEmpty == false
        // An interrupted credential write is not half a sign-in. Normalize the
        // pair so the root cannot enter the app with identity metadata but no
        // proof, or carry an unreachable session nobody can revoke.
        if signedInAccountID == nil || !hasSessionToken {
            // Keep an existing account binding across an ordinary sign-out so
            // a different Apple identity cannot inherit this phone's log.
            clearAccountSession(forgetAccount: signedInAccountID == nil)
        } else {
            isSignedIn = true
        }
        rebuildRecognizer()
        if isSignedIn {
            await synchronizeAccountHistory()
            if isSignedIn {
                resumeUnreadMessages()
                await refreshTables()
            }
        }
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
        if case .messageSent(let message) = payload {
            locallyRecordedMessageIDs.insert(message.id)
        }
        syncEvents([event])
    }

    func logMeal(_ meal: MealEntry) async {
        let resolved = resolveNutrition(in: meal, newStatus: .exact)
        await record(.mealLogged(resolved), occurredAt: resolved.eatenAt)
    }

    func reviseMeal(_ meal: MealEntry) async {
        var revised = resolveNutrition(in: meal, newStatus: .userConfirmed)
        revised.wasCorrected = true
        await record(.mealRevised(revised), occurredAt: revised.eatenAt)
    }

    /// Resolve every stored representation with the same pinned composition
    /// table before writing the event. Existing exact provenance survives;
    /// rows whose identity the person changed arrive with no resolution and
    /// are marked `user_confirmed` on a revision.
    private func resolveNutrition(
        in meal: MealEntry,
        newStatus: NutrientResolutionStatus
    ) -> MealEntry {
        guard let table = config.nutrientsPerGram else { return meal }
        func resolve(_ item: MealItem) -> MealItem {
            let status: NutrientResolutionStatus
            if let previous = item.resolution, previous.foodRef != nil {
                status = previous.status
            } else if item.resolution == nil {
                status = newStatus
            } else {
                status = .exact
            }
            return table.resolving(item, status: status)
        }

        var result = meal
        if var dishes = result.storedDishes {
            for index in dishes.indices {
                dishes[index].items = dishes[index].items.map(resolve)
            }
            result.storedDishes = dishes
            result.items = dishes.flatMap { $0.flattened() }
        } else {
            result.items = result.items.map(resolve)
        }
        return result
    }

    /// The event log keeps the deletion; the photograph does not get to outlive
    /// the meal it belonged to.
    func deleteMeal(_ meal: MealEntry) async {
        PhotoStore.shared.remove(meal.photoHash)
        await record(.mealDeleted(mealID: meal.id), occurredAt: meal.eatenAt)
    }

    func completeOnboarding() {
        hasOnboarded = true
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        UserDefaults.standard.set(onboardingVersion, forKey: Self.onboardingVersionKey)
    }

    func acceptPhotoProcessing() {
        hasAcceptedPhotoProcessing = true
        UserDefaults.standard.set(photoProcessingConsentVersion, forKey: "photoProcessingConsentVersion")
        resumeUnreadMessages()
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
            clearAccountSession(forgetAccount: true)
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
    ///
    /// Returns the message it wrote, because the reading screen has to watch
    /// one particular send rather than "whether anything is being read": two
    /// plates can be in flight at once — that is the whole point of not
    /// blocking the composer — and a screen that dismissed on
    /// `isReadingAnything` would close on whichever finished first and show the
    /// wrong meal. Nil when there was nothing to send.
    @discardableResult
    func send(said: String?, photo: Data? = nil) async -> LogMessage? {
        let normalized = photo.flatMap(ModelInputImage.render)
        let text = said?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = LogMessage(
            said: (text?.isEmpty ?? true) ? nil : text,
            photoHash: normalized.flatMap { PhotoStore.shared.store($0) }
        )
        guard !message.isEmpty else { return nil }

        await record(.messageSent(message), occurredAt: message.sentAt)
        read(message, bytes: normalized)
        return message
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
        where locallyRecordedMessageIDs.contains(message.id)
            && projection.meal(forMessage: message.id) == nil
            && messageStates[message.id] == nil {
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
            handleAccountError(error, prefix: "Reading meal")
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

    // MARK: - How much of it got written down
    //
    // The Today screen leads on days logged rather than on a meal rating, and
    // the distinction is the same one `DayLog.fill` already makes: this counts
    // *logging*, not eating well. A figure that dimmed because of what you ate
    // would turn a record into a report card, and the app has just spent a
    // release taking one of those out.

    /// The window the day counter is drawn against.
    ///
    /// Ninety days is the mock's number and it is a habit-forming span rather
    /// than a calendar one — nothing resets on the first of the month, so a
    /// good run in March is not erased by April.
    static let loggingWindow = 90

    /// Days in the last `days` with at least one meal on them.
    func daysLogged(inLast days: Int = AppModel.loggingWindow, calendar: Calendar = .current) -> Int {
        recentDays(days, calendar: calendar).count { $0.isLogged }
    }

    /// Consecutive days ending today with at least one meal.
    ///
    /// Today not being logged *yet* does not read as a broken streak — the same
    /// concession `movementStreak` makes, and for the same reason: at nine in
    /// the morning nobody has eaten anything worth a zero.
    func loggingStreak(calendar: Calendar = .current) -> Int {
        let logged = Set(
            projection.meals.values.map { calendar.startOfDay(for: Date(epochMillis: $0.eatenAt)) }
        )
        var streak = 0
        var day = calendar.startOfDay(for: Date())
        if !logged.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        while logged.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// One local day, with what it came to. Oldest first, gaps included — a day
    /// with nothing on it is a bar that has to be drawn at zero, not a column
    /// the chart quietly leaves out.
    struct DayNutrition: Identifiable, Equatable {
        /// The local midnight this day starts at, in seconds. Stable and
        /// orderable, and safe as a `ForEach` id in a way a `Date` is not.
        let id: Int
        let start: Date
        let mealCount: Int
        let total: NutrientTotal

        var isLogged: Bool { mealCount > 0 }
        var kcal: Double { total.nutrients.kcal }
        var protein: Double { total.nutrients.protein }
    }

    /// The last `count` days, oldest first, each totalled once.
    ///
    /// Bucketed in a single pass rather than by calling `meals(on:)` per day:
    /// the progress screen asks for ninety of these at a time and the naive
    /// shape walks the whole log ninety times.
    func dailyNutrition(
        _ count: Int,
        endingAt end: Date = Date(),
        calendar: Calendar = .current
    ) -> [DayNutrition] {
        let lastDay = calendar.startOfDay(for: end)
        // Keyed on the local midnight itself rather than on a day *number*
        // divided out of an epoch. Two of those can collide across a daylight
        // saving change, where a day is 23 hours long — and a collision here is
        // not a missing bar, it is one day quietly drawing another day's food.
        var byDay: [Date: [MealEntry]] = [:]
        for meal in projection.meals.values {
            let day = calendar.startOfDay(for: Date(epochMillis: meal.eatenAt))
            byDay[day, default: []].append(meal)
        }
        return (0..<max(1, count)).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .day, value: -offset, to: lastDay) else { return nil }
            let meals = byDay[start] ?? []
            return DayNutrition(
                id: Int(start.timeIntervalSince1970),
                start: start,
                mealCount: meals.count,
                total: nutrients(in: meals)
            )
        }
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
            && healthSnapshot.profile.isEmpty
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

    private static let nutritionProfileKey = "nutritionProfile.v1"

    /// Health values win when present; manually entered values remain as a
    /// fallback for fields Health does not contain or the person did not share.
    var nutritionProfile: NutritionProfile {
        var profile = manualNutritionProfile
        let health = healthSnapshot.profile
        if !nutritionProfileHealthOverrides.contains(.age), let value = health.ageYears {
            profile.ageYears = value
        }
        if !nutritionProfileHealthOverrides.contains(.referenceSex), let value = health.referenceSex {
            profile.referenceSex = value
        }
        if !nutritionProfileHealthOverrides.contains(.height), let value = health.heightCentimeters {
            profile.heightCentimeters = value
        }
        if !nutritionProfileHealthOverrides.contains(.weight), let value = health.weightKilograms {
            profile.weightKilograms = value
        }
        if !nutritionProfileHealthOverrides.contains(.bodyFat), let value = health.bodyFatPercentage {
            profile.bodyFatPercentage = value
        }
        if !nutritionProfileHealthOverrides.contains(.activity), let value = health.activityLevel {
            profile.activityLevel = value
        }
        return profile
    }

    /// Saves manual profile values without copying accepted Health values into
    /// stale fallbacks. A field in `overridingHealthFields` is the explicit
    /// exception: the person tapped Change in onboarding, so their value wins
    /// until they edit it again.
    func saveNutritionProfile(
        _ profile: NutritionProfile,
        overridingHealthFields: Set<NutritionProfileField> = []
    ) {
        nutritionProfileHealthOverrides.formUnion(overridingHealthFields)
        UserDefaults.standard.set(
            nutritionProfileHealthOverrides.map(\.rawValue).sorted(),
            forKey: "nutritionProfile.healthOverrides.v1"
        )

        // A resolved editor contains Health values as well as typed ones. Do not
        // silently turn those Health values into stale manual fallbacks when the
        // person changes only their goal or another unfilled field.
        var manual = profile
        let health = healthSnapshot.profile
        if health.ageYears != nil, !nutritionProfileHealthOverrides.contains(.age) {
            manual.ageYears = manualNutritionProfile.ageYears
        }
        if health.referenceSex != nil, !nutritionProfileHealthOverrides.contains(.referenceSex) {
            manual.referenceSex = manualNutritionProfile.referenceSex
        }
        if health.heightCentimeters != nil, !nutritionProfileHealthOverrides.contains(.height) {
            manual.heightCentimeters = manualNutritionProfile.heightCentimeters
        }
        if health.weightKilograms != nil, !nutritionProfileHealthOverrides.contains(.weight) {
            manual.weightKilograms = manualNutritionProfile.weightKilograms
        }
        if health.bodyFatPercentage != nil, !nutritionProfileHealthOverrides.contains(.bodyFat) {
            manual.bodyFatPercentage = manualNutritionProfile.bodyFatPercentage
        }
        if health.activityLevel != nil, !nutritionProfileHealthOverrides.contains(.activity) {
            manual.activityLevel = manualNutritionProfile.activityLevel
        }

        manualNutritionProfile = manual
        if let data = try? JSONEncoder().encode(manual) {
            UserDefaults.standard.set(data, forKey: Self.nutritionProfileKey)
        }
    }

    /// Health fields that still own their value. Explicit onboarding overrides
    /// are masked so Settings presents them as editable manual values instead
    /// of incorrectly labelling and disabling them as Health-owned.
    var editableHealthProfile: HealthProfileSnapshot {
        var health = healthSnapshot.profile
        if nutritionProfileHealthOverrides.contains(.age) { health.ageYears = nil }
        if nutritionProfileHealthOverrides.contains(.referenceSex) { health.referenceSex = nil }
        if nutritionProfileHealthOverrides.contains(.height) { health.heightCentimeters = nil }
        if nutritionProfileHealthOverrides.contains(.weight) { health.weightKilograms = nil }
        if nutritionProfileHealthOverrides.contains(.bodyFat) { health.bodyFatPercentage = nil }
        if nutritionProfileHealthOverrides.contains(.activity) { health.activityLevel = nil }
        return health
    }

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

    /// Nil until all required profile inputs are known. A missing input produces
    /// no reference rather than a default belonging to an imaginary person.
    var proteinTarget: Double? { dailyTargets?.protein }

    /// Energy and macro references from the same resolved profile.
    var dailyTargets: DailyTargets? {
        DailyTargets.forProfile(nutritionProfile)
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
        if token?.isEmpty == false, isSignedIn { syncEvents(loadedEvents) }
    }

    /// Persist the opaque proof and update the observable root gate. Kept as two
    /// setters so a Keychain failure can never be hidden by UserDefaults alone;
    /// normal UI uses `activateAccount` to write the pair and start repair.
    func setSessionToken(_ token: String?) {
        do {
            try keychain.set(token, for: .sessionToken)
            hasSessionToken = token?.isEmpty == false
        } catch {
            hasSessionToken = false
            cloudError = "Could not save your sign-in: \(error.localizedDescription)"
        }
        isSignedIn = hasSessionToken && signedInAccountID != nil
        rebuildRecognizer()
    }

    func rememberAccountID(_ accountId: String?) {
        signedInAccountID = accountId
        if let accountId {
            UserDefaults.standard.set(accountId, forKey: Self.accountIDDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.accountIDDefaultsKey)
        }
        isSignedIn = hasSessionToken && accountId != nil
    }

    /// Make the new identity the only production principal, then repair both
    /// directions before showing account-backed surfaces.
    func activateAccount(_ result: SignInResult) async {
        if let bound = signedInAccountID, bound != result.accountId {
            cloudError = "This phone's local meal log belongs to a different Apple account. Sign in with that account to open it."
            return
        }
        setSessionToken(result.sessionToken)
        rememberAccountID(result.accountId)
        await synchronizeAccountHistory()
        guard isSignedIn else { return }
        resumeUnreadMessages()
        await refreshTables()
    }

    /// Signing out is local even if the revocation request cannot reach the
    /// server. Retaining a dead or unreachable token traps the app behind 401s;
    /// the server session expires independently and can be revoked next time.
    func signOut() async {
        do {
            try await backend?.signOut()
        } catch {
            cloudError = "Sign out: \(error.localizedDescription)"
        }
        clearAccountSession()
    }

    private func clearAccountSession(forgetAccount: Bool = false) {
        try? keychain.set(nil, for: .sessionToken)
        hasSessionToken = false
        if forgetAccount {
            signedInAccountID = nil
            UserDefaults.standard.removeObject(forKey: Self.accountIDDefaultsKey)
        }
        isSignedIn = false
        tables = []
        tablesAsOf = nil
        rebuildRecognizer()
    }

    // MARK: - Tables

    /// Every table, refreshed on open.
    ///
    /// Polling, not push — APNs is not built, and the contract is honest about
    /// what that costs: every response carries `asOf`, the moment the server
    /// counted, so a badge can be drawn as the snapshot it is. A count with no
    /// time on it is a number pretending to be live.
    private(set) var tables: [TableSummary] = []
    /// When the server last counted. Nil before the first successful poll —
    /// which is a different fact from "no tables", and the row must not draw
    /// them the same way.
    private(set) var tablesAsOf: EpochMillis?
    private(set) var tablesError: String?
    /// A deep-linked table code survives the identity/onboarding gates. Joining
    /// is still confirmed by the person; opening a URL never mutates membership
    /// by itself.
    private(set) var pendingTableInviteCode: String?
    /// Rolling-API bridge: the old strict create endpoint cannot echo the new
    /// privacy object. Keep the choice on this device until the current server
    /// owns it, so an intentionally hidden photo is never re-enabled by a nil
    /// field in an older response.
    private var tableVisibilityOverrides: [String: TableVisibility] = {
        guard let data = UserDefaults.standard.data(forKey: AppModel.tableVisibilityOverridesKey),
              let values = try? JSONDecoder().decode([String: TableVisibility].self, from: data)
        else { return [:] }
        return values
    }()

    /// The one table the day page's slim row names. The loudest — most unread —
    /// then the most recently posted in, so a quiet table cannot sit in front
    /// of one with something new in it.
    var loudestTable: TableSummary? {
        tables.max {
            $0.unreadCount == $1.unreadCount
                ? ($0.latest?.createdAt ?? 0) < ($1.latest?.createdAt ?? 0)
                : $0.unreadCount < $1.unreadCount
        }
    }

    var totalUnread: Int { tables.reduce(0) { $0 + $1.unreadCount } }

    func handleIncomingURL(_ url: URL) {
        guard url.scheme?.lowercased() == "eatsome",
              ["table", "join"].contains(url.host?.lowercased() ?? ""),
              let rawCode = url.pathComponents.dropFirst().first
        else { return }
        let code = rawCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (6...20).contains(code.count) else { return }
        pendingTableInviteCode = code
    }

    func clearPendingTableInvite() {
        pendingTableInviteCode = nil
    }

    func tableVisibility(for table: TableSummary) -> TableVisibility {
        table.visibility ?? tableVisibilityOverrides[table.id] ?? .privateByDefault
    }

    func refreshTables(calendar: Calendar = .current) async {
        guard let backend else { return }
        // The server cannot know where this phone's midnight is, so "cooked
        // today" is counted from a boundary this side supplies.
        let since = calendar.startOfDay(for: Date()).epochMillis
        do {
            let response = try await backend.tables(since: since)
            tables = response.tables
            tablesAsOf = response.asOf
            tablesError = nil
        } catch {
            // A failed poll leaves the last snapshot on screen rather than
            // blanking it: an empty list would say "you are in no tables",
            // which is a claim, where a stale one says only that it is stale.
            tablesError = error.localizedDescription
            handleAccountError(error, prefix: "Tables")
        }
    }

    func markTableRead(_ table: TableSummary, upTo seq: Int) async {
        guard let backend, seq > table.myLastReadSeq else { return }
        try? await backend.markRead(seq: seq, in: table.id)
        await refreshTables()
    }

    enum TablesError: LocalizedError {
        case noBackend
        var errorDescription: String? {
            "eatsome cannot reach its backend. Add an access token in the workshop."
        }
    }

    @discardableResult
    func createTable(
        named name: String,
        as displayName: String = "You",
        visibility: TableVisibility = .privateByDefault
    ) async throws -> TableSummary {
        guard let backend else { throw TablesError.noBackend }
        let table = try await backend.createTable(
            .init(name: name, displayName: displayName, visibility: visibility)
        )
        tableVisibilityOverrides[table.id] = visibility
        persistTableVisibilityOverrides()
        await refreshTables()
        return tables.first(where: { $0.id == table.id }) ?? table
    }

    func joinTable(code: String, as displayName: String) async throws {
        guard let backend else { throw TablesError.noBackend }
        _ = try await backend.joinTable(.init(code: code, displayName: displayName))
        await refreshTables()
    }

    /// The redaction happens here, once, at the moment of the tap — see
    /// `MealEntry.shareable(showingIngredients:)`. Nothing downstream re-derives
    /// it, because the post is a copy rather than a reference into the log.
    func share(
        _ meal: MealEntry,
        to table: TableSummary,
        caption: String,
        showingIngredients: Bool
    ) async throws {
        guard let backend else { throw TablesError.noBackend }
        let trimmed = caption.trimmingCharacters(in: .whitespaces)
        _ = try await backend.post(
            .share(
                id: UUIDv7.generate().uuidString,
                mealId: meal.id.uuidString,
                dishName: MealDisplay.title(meal),
                caption: trimmed.isEmpty ? nil : trimmed,
                ingredients: meal.shareable(
                    showingIngredients: showingIngredients && tableVisibility(for: table).nutrition
                ),
                photoHash: tableVisibility(for: table).photos ? meal.photoHash : nil
            ),
            to: table.id
        )
        await refreshTables()
    }

    private func persistTableVisibilityOverrides() {
        guard let data = try? JSONEncoder().encode(tableVisibilityOverrides) else { return }
        UserDefaults.standard.set(data, forKey: Self.tableVisibilityOverridesKey)
    }

    func updateTableNote(_ note: String?, for post: TablePost, in table: TableSummary) async throws -> String? {
        guard let backend else { throw TablesError.noBackend }
        return try await backend.updateTableNote(postID: post.id, note: note, in: table.id)
    }

    /// A friend's dish, saved into your own log as your own meal.
    ///
    /// A new `MealEntry` with a new id, not a copy of theirs: it is now
    /// something you ate, it updates your meal rating, and you can correct it
    /// in words like anything else. `source` is `.recipe` because that is what
    /// it is — a repeat of something already checked by somebody — and the note
    /// records where it came from so the provenance survives a correction.
    func saveSharedDish(_ post: TablePost, ingredients: [PostIngredient]) async {
        let items = ingredients.map {
            MealItem(kind: $0.kind, label: $0.label, dish: post.dishName, grams: $0.grams)
        }
        let meal = MealEntry(
            eatenAt: Date().epochMillis,
            items: items,
            source: .recipe,
            note: "Saved from \(post.authorName)'s \(post.dishName ?? "dish")",
            wasCorrected: false
        )
        await logMeal(meal)
    }

    var currentBackend: BackendSession? { backend }

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
            sessionToken: (try? keychain.get(.sessionToken)) ?? nil,
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

    /// Push a write without delaying the local append. The account session, not
    /// the shared app credential or device id, is the production boundary.
    private func syncEvents(_ events: [LoggedEvent]) {
        guard isSignedIn, let backend, !events.isEmpty else { return }
        Task {
            do {
                try await backend.syncEvents(events)
                cloudError = nil
            } catch {
                handleAccountError(error, prefix: "Cloud sync")
            }
        }
    }

    /// Repair both halves of the append-only account log. Upload first so this
    /// install's pre-account history is part of the union the following GET
    /// returns; then append only missing ids locally and replay the total order.
    func synchronizeAccount() async {
        await synchronizeAccountHistory()
        if isSignedIn { await refreshTables() }
    }

    private func synchronizeAccountHistory() async {
        guard isSignedIn, !isSynchronizingAccount, let backend else { return }
        isSynchronizingAccount = true
        defer { isSynchronizingAccount = false }
        do {
            if !loadedEvents.isEmpty { try await backend.syncEvents(loadedEvents) }
            let remote = try await backend.events()
            let existing = Set(loadedEvents.map(\.id))
            let missing = remote.filter { !existing.contains($0.id) }
            if !missing.isEmpty {
                try await log?.append(missing)
                loadedEvents.append(contentsOf: missing)
                loadedEvents = loadedEvents.enumerated().sorted { lhs, rhs in
                    lhs.element.recordedAt == rhs.element.recordedAt
                        ? lhs.offset < rhs.offset
                        : lhs.element.recordedAt < rhs.element.recordedAt
                }.map(\.element)
                projection = Projection(replaying: loadedEvents)
            }
            await restoreMissingMealPhotos(using: backend)
            cloudError = nil
        } catch {
            handleAccountError(error, prefix: "Cloud sync")
        }
    }

    /// Event sync restores the durable meal records; photographs are private R2
    /// objects addressed by the hashes in those records. Rehydrate only absent
    /// local files and keep a small concurrency ceiling so a reinstall with a
    /// long history does not burst every download at the Worker at once.
    private func restoreMissingMealPhotos(using backend: BackendSession) async {
        let hashes = Set(projection.meals.values.compactMap(\.photoHash))
            .filter { !PhotoStore.shared.contains($0) }
            .sorted()
        guard !hashes.isEmpty else { return }

        var pending = hashes.makeIterator()
        await withTaskGroup(of: (String, Data?).self) { group in
            func add(_ hash: String) {
                group.addTask {
                    (hash, try? await backend.mealPhoto(hash: hash))
                }
            }

            for _ in 0..<min(4, hashes.count) {
                if let hash = pending.next() { add(hash) }
            }
            while let (hash, data) = await group.next() {
                if let data { PhotoStore.shared.restore(data, for: hash) }
                if let next = pending.next() { add(next) }
            }
        }
    }

    private func handleAccountError(_ error: any Error, prefix: String) {
        if case BackendError.http(let status, _) = error, status == 401 {
            cloudError = "Your sign-in expired. Sign in with Apple again."
            clearAccountSession()
        } else {
            cloudError = "\(prefix): \(error.localizedDescription)"
        }
    }
}
