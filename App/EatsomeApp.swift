import SwiftUI

@main
struct EatsomeApp: App {
    @State private var account: EatsomeAccount
    @State private var store: EatsomeStore

    init() {
        #if DEBUG
        // A device-side escape hatch for exercising onboarding without
        // uninstalling the app and losing its local meal/photo cache. Editing
        // the preferences plist from a Mac is insufficient because cfprefsd
        // may still serve its in-memory value to the next process.
        if ProcessInfo.processInfo.environment["EATSOME_RESET_ONBOARDING"] == "1" {
            UserDefaults.standard.removeObject(forKey: "eatsome.profile.v1")
        }
        #endif

        // Two lanes, and the store holds the account rather than the other way
        // round: a write is appended locally and *then* mirrored, so the thing
        // that appends is the thing that knows where to send it.
        let account = EatsomeAccount()
        _account = State(initialValue: account)
        _store = State(initialValue: EatsomeStore(account: account))

        // The identity is General Sans and Space Grotesk, bundled, eight cuts
        // between them. If any of them ever falls
        // out of the target's resources, `UIFont(name:)` returns nil and SwiftUI
        // quietly renders the system face instead — no crash, no warning, and
        // every size and weight in `WellieTheme` still tuned for a typeface that
        // is not on screen. That is the same shape of failure as the month the
        // Gemini schema stopped emitting weights: everything works, and
        // everything is wrong. So it is loud in development and survivable in
        // production, where a fallback face beats a crash.
        assert(
            WellieTheme.fontsAreInstalled,
            "A bundled font is missing — check UIAppFonts in project.yml, re-run scripts/build-fonts.py, and re-run scripts/bootstrap.sh"
        )
    }

    var body: some Scene {
        WindowGroup {
            // No `preferredColorScheme` anywhere below, deliberately, and the
            // absence is the decision: the app follows the phone. It used to
            // force `.dark`, correctly at the time — only the dark half had
            // been drawn, and following the system would have handed half the
            // users a light app nobody designed. Both halves exist now
            // (`WellieTheme` is pairs all the way down, each side checked for
            // contrast against its own page), so overriding a system-wide
            // preference would just be an opinion about someone else's phone.
            EatsomeRoot()
                .environment(account)
                .environment(store)
        }
    }
}
