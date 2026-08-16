import EatsomeCore
import Observation
import SwiftUI

/// What the screens read from.
///
/// A fold over the log and nothing else. The previous model grew to two
/// thousand lines because every screen's question was answered by another
/// stored property; here the log is the state, `Projection` is the fold, and a
/// screen's question is a computed property over it. Identity and the Worker
/// are the other lane — see `EatsomeAccount` — because they fail separately: a
/// phone with no network still logs meals.
@MainActor
@Observable
final class EatsomeStore {
    /// The log this store folds. Nil only if the container could not be opened,
    /// which is a broken install rather than a state to design for.
    private var log: EventLog?

    private(set) var projection = Projection()
    private(set) var loadError: String?
    /// Records written by a build newer than this one. They are carried and
    /// re-uploaded, never displayed, and this count is what settings shows so
    /// their absence from the screens is stated rather than mysterious.
    private(set) var fromNewerBuild = 0
    /// Lines that are not a record at all. Non-empty means this phone must not
    /// reconcile: it cannot speak for a history it cannot read.
    private(set) var corruptLines = 0

    /// Every event this phone holds, in the order the file has them. Kept
    /// because the push sends the whole log: the Worker unions by id, so
    /// sending everything is how a write that lost its network race is
    /// repaired without anybody tracking which ones those were.
    private var events: [LoggedEvent] = []

    /// True for the whole span of a `synchronize`. It keeps `record` from
    /// starting a second upload alongside the one already in flight, and keeps
    /// a second `synchronize` — a foreground return landing on top of a launch
    /// — from running at all.
    private var isSynchronizing = false

    /// The account this log is mirrored under. Held rather than injected per
    /// call so `record` can push a write up without the append waiting for it.
    let account: EatsomeAccount

    /// The body details that produce the day's references.
    ///
    /// Not in the event log. The log records what happened; this is who you
    /// are, it has no history worth replaying, and putting it in the log would
    /// mean every screen that wants your height folds a thousand events to
    /// find the newest one.
    var profile: NutritionProfile {
        didSet { persistProfile() }
    }

    /// Nil until the details are known, and a nil here means the screens print
    /// figures with no denominator rather than inventing one for an imaginary
    /// person.
    var dailyTargets: DailyTargets? { DailyTargets.forProfile(profile) }

    private static let profileKey = "eatsome.profile.v1"

    init(account: EatsomeAccount) {
        self.account = account
        if let raw = UserDefaults.standard.string(forKey: Self.profileKey),
           let decoded = try? JSONDecoder().decode(NutritionProfile.self, from: Data(raw.utf8)) {
            profile = decoded
        } else {
            profile = NutritionProfile()
        }
    }

    private func persistProfile() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(String(decoding: data, as: UTF8.self), forKey: Self.profileKey)
    }

    func bootstrap() async {
        do {
            let log = try EventLog(url: try EventLog.defaultURL())
            self.log = log
            try await reload(log)
        } catch {
            loadError = "Could not open your history: \(error.localizedDescription)"
        }
    }

    private func reload(_ log: EventLog) async throws {
        let loaded = try await log.load()
        events = loaded.events
        projection = Projection(replaying: loaded.events)
        fromNewerBuild = loaded.fromNewerBuild
        corruptLines = loaded.corrupt.count
        // Said, not hidden — a line that would not parse is missing from every
        // total on every screen, and silence about it is how you stop trusting
        // your own history six months later. It no longer stops anything: the
        // mirror unions by id in both directions and neither side deletes, so
        // a phone that cannot read one line can still safely pull and push.
        loadError = loaded.corrupt.isEmpty
            ? nil
            : "\(loaded.corrupt.count) \(loaded.corrupt.count == 1 ? "entry" : "entries") in your history could not be read, and are not counted in any total."
    }

    /// Pull, then push, then fetch back the pictures.
    ///
    /// In that order, and the order is the design. Pulling first means a
    /// reinstall gets its history before it says anything about it, so the push
    /// that follows is a comparison rather than an upload of an empty file over
    /// a full account. Photographs come last because they are addressed by the
    /// hashes in the records, and until the records are back there is nothing
    /// to ask for.
    ///
    /// Nothing here deletes. A meal that is gone is gone because a
    /// `mealDeleted` event says so on both sides — not because one side failed
    /// to mention it.
    ///
    /// Re-entrant calls return immediately, and while one is running `record`
    /// stops mirroring. Two overlapping uploads would only cost bandwidth — the
    /// Worker unions by id — but the sync is the wider of the two and covers
    /// the narrower for free: it pushes `events` at the end, which by then
    /// includes anything appended while it was pulling.
    func synchronize() async {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }

        if account.logBelongsToAnotherAccount { await discardLocalHistory() }
        account.claimLog()

        guard let log else { return }
        let pulled = await account.pull()
        if !pulled.isEmpty {
            do {
                let added = try await log.append(lines: pulled)
                if !added.isEmpty { try await reload(log) }
            } catch {
                loadError = "Could not save history from your account: \(error.localizedDescription)"
            }
        }
        await account.push(events)
        await account.restoreMissingPhotos(Set(projection.meals.values.compactMap(\.photoHash)))

        // A meal logged *during* the push above skipped its own mirror and
        // arrived too late for that push to have seen it, so without this it
        // would sit on the phone until the next meal or the next foreground.
        // Costs nothing when there is nothing to send: `push` returns as soon
        // as it finds the watermark already at the end of the log.
        account.mirror(events)
    }

    /// Append, fold, mirror, and let the screens redraw.
    ///
    /// The log is written first so a crash between the two loses nothing, and
    /// the mirror is started rather than awaited so a slow network never delays
    /// a meal appearing on Today. A write that loses its race is repaired by
    /// the next `synchronize`, because the push watermark only moves on success.
    ///
    /// The whole log goes to `mirror`, not the one new event: the watermark in
    /// `EatsomeAccount` decides what actually leaves, and it needs the same
    /// list every caller sees to do that.
    func record(_ payload: EventPayload, occurredAt: EpochMillis = Date().epochMillis) async {
        // A nil log used to be optional-chained past, which wrote nothing,
        // threw nothing, and let the meal appear on Today and go up to the
        // account while the file on this phone never heard about it. Nil is a
        // container that could not be opened; it is rare and it is loud.
        guard let log else {
            loadError = "Could not write to your history: this phone has no open log."
            return
        }
        let event = LoggedEvent(occurredAt: occurredAt, payload: payload)
        do {
            try await log.append(event)
        } catch {
            loadError = "Could not write to your history: \(error.localizedDescription)"
            return
        }
        events.append(event)
        projection.apply(event)
        if !isSynchronizing { account.mirror(events) }
    }

    // MARK: Changing hands

    /// Throw the local history away, because it is not this account's.
    ///
    /// Only ever reached when a *different* account has just signed in on a
    /// phone that already had a log. Without it the new account's push
    /// watermark is 0, so the previous person's meals and photographs would go
    /// up under the new account's name on the very next sync — which is a leak,
    /// not a merge.
    ///
    /// **This is safe only because the mirror is two-way.** Deleting the file
    /// is not losing the history: the previous account pushed it as it was
    /// written, and signing back in on this or any phone pulls it down again.
    /// Under the old push-only design this would have been the sole copy.
    ///
    /// The exception, and it is a real one: anything that account wrote while
    /// offline and never pushed is only here. It cannot be rescued at this
    /// point — its session was revoked at sign-out and this phone has no
    /// credential that can speak for it — which is why `signOut` pushes first.
    private func discardLocalHistory() async {
        PhotoStore.shared.removeAll()
        events = []
        projection = Projection()
        fromNewerBuild = 0
        corruptLines = 0
        loadError = nil
        do {
            let url = try EventLog.defaultURL()
            try? FileManager.default.removeItem(at: url)
            log = try EventLog(url: url)
        } catch {
            log = nil
            loadError = "Could not start a fresh history on this phone: \(error.localizedDescription)"
        }
    }

    /// Leave the account, having first made sure it is taking everything with
    /// it.
    ///
    /// The push has to happen here rather than after, because signing out
    /// revokes the session: a meal written offline and still behind the
    /// watermark has exactly this one moment left in which it can be uploaded.
    /// If the phone is offline now, the push fails, the watermark holds, and
    /// signing back into the same account still finds the log and sends it —
    /// the only case that loses it is signing in as somebody *else* next, which
    /// is the trade `discardLocalHistory` makes deliberately.
    func signOut() async {
        await account.push(events)
        await account.signOut()
    }

    // MARK: What Today asks

    /// The day, in one column, newest first.
    ///
    /// Meals and nothing else. Workouts and sleep were unioned in here from a
    /// live Health read, which made this the one place two things with different
    /// lifetimes met; the day is now a fold over the log alone, and `TodayEntry`
    /// — the enum that existed to hold the union — went with them.
    func today(_ day: Date = Date()) -> [MealEntry] {
        projection.meals(on: day).sorted { $0.eatenAt > $1.eatenAt }
    }

    func nutrients(on day: Date = Date()) -> Nutrients { projection.nutrients(on: day) }

    /// Ninety days, and the window is a property of the screen rather than of
    /// the data — it is what "6 / 90 days" is counting against.
    static let loggingWindow = 90

    func daysLogged(endingAt end: Date = Date()) -> Int {
        projection.daysLogged(Self.loggingWindow, endingAt: end)
    }

    // MARK: Removing one

    /// Take a meal out of the history.
    ///
    /// `mealDeleted` is another line, not an erasure — the file is append-only
    /// and the projection is what forgets. The photograph goes with it, and
    /// only if no meal that survives still names it: two meals can share a
    /// picture when one was read twice.
    func delete(_ meal: MealEntry) async {
        await record(.mealDeleted(mealID: meal.id), occurredAt: meal.eatenAt)
        if let hash = meal.photoHash,
           !projection.meals.values.contains(where: { $0.photoHash == hash }) {
            PhotoStore.shared.remove(hash)
        }
    }
}
