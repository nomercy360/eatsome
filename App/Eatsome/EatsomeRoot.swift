import EatsomeCore
import SwiftUI

/// What the app opens on: a wait, a gate, or the shell.
///
/// The wait is short and it is not decoration. Deciding "signed out" before the
/// Keychain has been looked in flashes the sign-in wall at somebody who is
/// signed in, every launch — which is the same class of mistake as a font
/// falling back silently: everything works, and everything is wrong for a beat.
///
/// Sync is driven here rather than from either lane, because it needs both: a
/// log to union into and an account to union with. It runs at the three moments
/// the two can have drifted apart — launch, a sign-in landing, and coming back
/// to the app after being away — and it is cheap at all three because the pull
/// is incremental and the push is idempotent.
struct EatsomeRoot: View {
    @Environment(EatsomeAccount.self) private var account
    @Environment(EatsomeStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    @State private var opened = false

    var body: some View {
        Group {
            if !account.isReady || !opened {
                ProgressView()
                    .tint(WellieTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if account.isSignedIn {
                EatsomeShell()
            } else {
                SignInGate()
                    .transition(.opacity)
            }
        }
        .wellieScreen()
        .task {
            account.bootstrap()
            await store.bootstrap()
            opened = true
            await store.synchronize()
        }
        // A sign-in is the moment the two histories meet: whatever was logged
        // on this phone before it may have just been adopted by the account,
        // and whatever the account already held has to come back — the records
        // first and then the photographs, which are only ever addressed by the
        // hashes in those records.
        .onChange(of: account.isSignedIn) { was, now in
            guard !was, now else { return }
            Task { await store.synchronize() }
        }
        // And coming back to the app, because the other phone was logging while
        // this one was in a pocket. Cheap: the cursor means the pull asks for
        // what happened since, not for the history.
        .onChange(of: scenePhase) { was, now in
            guard now == .active, was != .active, opened, account.isSignedIn else { return }
            Task { await store.synchronize() }
        }
    }
}
