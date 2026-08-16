import EatsomeCore
import Observation
import SwiftUI

/// Who this phone is, and everything it says to the Worker.
///
/// The second lane beside `EatsomeStore`. The store folds the log; this holds
/// the credential the log is mirrored under and the one `BackendSession` built
/// from it. They are separate because they fail separately: a phone with no
/// network still logs meals, and a phone that cannot read its own history must
/// not be allowed to speak for it.
///
/// Three things live here and nowhere else:
///
/// - **The session token is the only credential.** It is minted by the Worker
///   in exchange for Apple's identity token, kept in the Keychain, and rebuilt
///   into `BackendSession` whenever it changes. Apple's own token is never
///   stored: it lives about ten minutes and proves a sign-in, not a session.
/// - **Consent precedes the first send.** Access to a camera is not consent to
///   cloud storage or to disclosure to a model provider, so the two are asked
///   separately and this one is versioned — a change to what is sent asks
///   again rather than inheriting an answer to a different question.
/// - **The mirror is two-way and nothing deletes.** The phone pulls what it
///   lacks and pushes what the Worker lacks; both sides union by id and neither
///   removes the other's rows. That is what makes a reinstall or a second phone
///   recover a history rather than erase one — and it is why a deletion has to
///   be a `mealDeleted` event like every other write, not an absence.
@MainActor
@Observable
final class EatsomeAccount {
    /// False until the Keychain has been read. The shell waits on it, because
    /// deciding "signed out" before the credential has been looked for flashes
    /// the sign-in wall at somebody who is signed in.
    private(set) var isReady = false
    private(set) var isSignedIn = false
    /// Not proof of anything and not secret — it is what lets two phones be
    /// seen landing on the same account. The token that proves it is in the
    /// Keychain.
    private(set) var accountID: String?
    /// The last thing that went wrong reaching the Worker, in words a person
    /// can read. Nil is not "everything worked", it is "nothing has failed
    /// since the last success".
    private(set) var error: String?
    private(set) var hasAgreedToSend: Bool
    private(set) var isDeletingData = false

    /// The Worker boundary, or nil when this build has no base URL or no
    /// device id to name a partition with. Nil is a broken build, not a state
    /// to design screens around.
    private(set) var session: BackendSession?

    private let keychain = KeychainStore()
    private var deviceID: String?
    private var isMirroring = false

    /// Bumped when what leaves the phone changes. An old answer then stops
    /// counting, because it was given about something else.
    private static let consentVersion = "send-2026-08-16-v1"
    private static let consentKey = "eatsome.consent.send"
    private static let accountIDKey = "eatsome.account.id"
    private static let logOwnerKey = "eatsome.log.owner"

    init() {
        hasAgreedToSend =
            UserDefaults.standard.string(forKey: Self.consentKey) == Self.consentVersion
        accountID = UserDefaults.standard.string(forKey: Self.accountIDKey)
        logOwnerID = UserDefaults.standard.string(forKey: Self.logOwnerKey)
    }

    // MARK: - Launch

    func bootstrap() {
        deviceID = stableDeviceID()
        let token = (try? keychain.get(.sessionToken)) ?? nil
        isSignedIn = !(token?.isEmpty ?? true) && accountID != nil
        rebuild(with: token)
        isReady = true
    }

    /// One `BackendSession`, rebuilt whenever the credential moves. The type is
    /// a value, so the alternative is a stale copy held by whoever asked first.
    private func rebuild(with token: String?) {
        guard let baseURL = Self.baseURL, let deviceID else {
            session = nil
            return
        }
        // There is no provider to name. The Worker asks Gemini and the phone
        // holds no model credential, so what goes up is a session and a device
        // id and nothing about which vendor answers.
        session = BackendSession(configuration: .init(
            baseURL: baseURL,
            deviceID: deviceID,
            sessionToken: token
        ))
    }

    private static var baseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "EatsomeAPIBaseURL") as? String,
              !value.isEmpty
        else { return nil }
        return URL(string: value)
    }

    /// The id that names this install's partition. Generated once and kept in
    /// the Keychain, so a reinstall that restores it keeps its history.
    private func stableDeviceID() -> String? {
        if let saved = (try? keychain.get(.deviceID)) ?? nil, !saved.isEmpty { return saved }
        let created = UUIDv7.generate().uuidString
        do {
            try keychain.set(created, for: .deviceID)
            return created
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// The privacy policy the Worker serves, derived from the base URL rather
    /// than pasted in, so a build pointed elsewhere links to that Worker's
    /// policy instead of silently to production's.
    var privacyURL: URL? { Self.baseURL?.appending(path: "privacy") }

    // MARK: - Consent

    func agreeToSend() {
        UserDefaults.standard.set(Self.consentVersion, forKey: Self.consentKey)
        hasAgreedToSend = true
    }

    /// Withdrawing consent is not a flag on its own — it deletes what was sent.
    /// A screen that let someone take the permission back while the pictures
    /// stayed would be describing something that did not happen.
    func revokeSendConsent() async {
        await deleteCloudData()
        UserDefaults.standard.removeObject(forKey: Self.consentKey)
        hasAgreedToSend = false
    }

    // MARK: - Identity

    /// Trade Apple's signed claim for a session. The phone decides nothing
    /// here: it carries the claim, and the Worker is the only thing that
    /// believes a `sub`.
    func signIn(_ credential: AppleSignIn.Credential) async {
        guard let session else {
            error = "This build cannot reach the eatsome service."
            return
        }
        do {
            let result = try await session.signIn(
                provider: .apple,
                identityToken: credential.identityToken,
                nonce: credential.nonce
            )
            try keychain.set(result.sessionToken, for: .sessionToken)
            UserDefaults.standard.set(result.accountId, forKey: Self.accountIDKey)
            accountID = result.accountId
            isSignedIn = true
            rebuild(with: result.sessionToken)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Leave the account on this phone. Local history stays on disk — signing
    /// out of a phone is not asking for it to be erased — and signing back into
    /// the same account picks it up where it was.
    ///
    /// `logOwnerID` deliberately survives this. It is what the *file* belongs
    /// to, not who is signed in, and it is the only thing that can tell the
    /// next sign-in whether the log it finds is that person's.
    func signOut() async {
        try? await session?.signOut()
        clearSession(forgetAccount: true)
    }

    // MARK: - Whose log is this

    /// The account the local log was written under.
    ///
    /// Separate from `accountID` and deliberately outlives it: `accountID` is
    /// who is signed in *now* and is cleared by signing out, while the file on
    /// disk is not. Comparing the new sign-in against `accountID` would
    /// therefore never fire on the one path that matters — sign out, then sign
    /// in as somebody else — because by then there is nothing to compare to.
    private(set) var logOwnerID: String?

    /// True when the signed-in account is not the one the log on this phone was
    /// written by. The log has to go before that account is allowed to see it.
    var logBelongsToAnotherAccount: Bool {
        guard let accountID, let logOwnerID else { return false }
        return accountID != logOwnerID
    }

    /// Record that the log on this phone is now this account's. Called once the
    /// log is known to hold nothing anybody else wrote.
    func claimLog() {
        guard let accountID, accountID != logOwnerID else { return }
        UserDefaults.standard.set(accountID, forKey: Self.logOwnerKey)
        logOwnerID = accountID
    }

    /// Erase what the account holds on the Worker. The local log is untouched:
    /// this is about the copy, not the record.
    func deleteCloudData() async {
        guard let session else { return }
        isDeletingData = true
        defer { isDeletingData = false }
        do {
            try await session.deleteAccountData()
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func clearSession(forgetAccount: Bool) {
        try? keychain.set(nil, for: .sessionToken)
        isSignedIn = false
        if forgetAccount {
            UserDefaults.standard.removeObject(forKey: Self.accountIDKey)
            accountID = nil
        }
        rebuild(with: nil)
    }

    // MARK: - The mirror

    /// Copy the log up without making the local append wait for it.
    ///
    /// Takes the *whole* log, like `push`, rather than the one event just
    /// written: the watermark decides what actually goes, and it can only do
    /// that if it is handed the same list every caller sees. A write that loses
    /// its network race leaves the watermark where it was, so the next push
    /// carries it.
    func mirror(_ all: [LoggedEvent]) {
        Task { await push(all) }
    }

    /// Everything the account holds that this phone does not, as raw lines.
    ///
    /// Pulled before anything is pushed, and the order is the whole design: a
    /// reinstall arrives with an empty file, and pulling first means the push
    /// that follows is a no-op rather than an upload of nothing over a history.
    ///
    /// The cursor is opaque and kept per account, because it names a position
    /// in *that* account's stream. Signing in as somebody else has to start
    /// from the beginning, and a cursor left over from the previous account
    /// would silently skip everything before it.
    func pull() async -> [RawJSON] {
        guard isSignedIn, let session, let accountID else { return [] }

        var lines: [RawJSON] = []
        var cursor = UserDefaults.standard.string(forKey: Self.cursorKey(accountID))
        do {
            repeat {
                let page = try await session.pullEvents(after: cursor)
                lines += page.lines
                cursor = page.cursor
                // Written each page rather than at the end, so a pull that
                // fails halfway does not re-download what it already appended.
                UserDefaults.standard.set(cursor, forKey: Self.cursorKey(accountID))
            } while cursor != nil
            error = nil
        } catch {
            report(error)
        }
        return lines
    }

    /// Push the part of the log the account has not confirmed.
    ///
    /// The watermark is a **count of lines in file order**, not a set of ids,
    /// and the whole design rests on the log being append-only: line *n* never
    /// changes, so "the first `pushedCount` lines are on the server" stays true
    /// forever once it is true. That is what lets one integer replace
    /// per-event bookkeeping. It moves only after `syncEvents` returns, so a
    /// failed push leaves it alone and the next one covers the same span.
    ///
    /// Two things it deliberately tolerates rather than prevents, because both
    /// are cheap and the alternative is bookkeeping:
    ///
    /// - Lines pulled from the account land *after* the watermark and are sent
    ///   straight back once. The Worker unions by id, so it costs one
    ///   comparison and never a duplicate.
    /// - Two pushes overlapping — a `mirror` racing a `synchronize` — send
    ///   overlapping slices. Also deduped. The store keeps them apart anyway;
    ///   this is what happens if it ever fails to.
    func push(_ all: [LoggedEvent]) async {
        guard isSignedIn, let session else { return }

        var start = pushedCount
        // The file is shorter than the watermark, so it is not the file the
        // watermark was counting — a truncated log, or defaults restored over
        // a fresh install. Start again rather than skip: re-sending is free and
        // silently never uploading somebody's history is not.
        if start > all.count { start = 0 }

        let pending = Array(all[start...])
        guard !pending.isEmpty else { return }
        do {
            try await session.syncEvents(pending)
            pushedCount = all.count
            error = nil
        } catch {
            report(error)
        }
    }

    /// How many lines of the local log this account has confirmed.
    ///
    /// Keyed by account for the same reason the pull cursor is: it describes a
    /// conversation with one account, and a count left over from a different
    /// one would skip a history that had never been sent anywhere. A new
    /// account reads 0 by construction, so there is nothing to reset.
    private var pushedCount: Int {
        get {
            guard let accountID else { return 0 }
            return UserDefaults.standard.integer(forKey: Self.pushedKey(accountID))
        }
        set {
            guard let accountID else { return }
            UserDefaults.standard.set(newValue, forKey: Self.pushedKey(accountID))
        }
    }

    private static func cursorKey(_ accountID: String) -> String {
        "eatsome.pull.cursor.\(accountID)"
    }

    private static func pushedKey(_ accountID: String) -> String {
        "eatsome.push.count.\(accountID)"
    }

    /// Fetch back any meal photograph this phone is missing.
    ///
    /// After the pull, deliberately: a reinstall only knows which hashes to ask
    /// for once the meals naming them are back.
    func restoreMissingPhotos(_ hashes: Set<String>) async {
        guard isSignedIn, let session else { return }
        await restorePhotos(hashes, using: session)
    }

    /// Event sync brings back the meal records; the pictures are private
    /// objects addressed by the hashes in them. Only absent files are fetched,
    /// and four at a time, so a reinstall with a long history does not open a
    /// hundred connections at once.
    private func restorePhotos(_ hashes: Set<String>, using session: BackendSession) async {
        let missing = hashes.filter { !PhotoStore.shared.contains($0) }.sorted()
        guard !missing.isEmpty else { return }

        var pending = missing.makeIterator()
        await withTaskGroup(of: (String, Data?).self) { group in
            func add(_ hash: String) {
                group.addTask { (hash, try? await session.mealPhoto(hash: hash)) }
            }
            for _ in 0..<min(4, missing.count) {
                if let hash = pending.next() { add(hash) }
            }
            while let (hash, data) = await group.next() {
                if let data { PhotoStore.shared.restore(data, for: hash) }
                if let next = pending.next() { add(next) }
            }
        }
    }

    /// An expired credential is not a network error, and saying "try again"
    /// about it would send somebody round a loop that cannot end. It clears the
    /// session so the gate comes back, and keeps the account id so signing in
    /// again lands on the same history.
    private func report(_ error: any Error) {
        if case BackendError.http(let status, _) = error, status == 401 {
            self.error = "Your sign-in expired. Sign in with Apple again."
            clearSession(forgetAccount: false)
        } else {
            self.error = error.localizedDescription
        }
    }
}
