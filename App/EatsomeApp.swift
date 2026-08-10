import ShamanCore
import SwiftUI

@main
struct EatsomeApp: App {
    @State private var model = AppModel()

    init() {
        // The identity is Space Grotesk and IBM Plex Mono, bundled. If either
        // ever falls out of the target's resources, `UIFont(name:)` returns nil
        // and SwiftUI quietly renders the system face instead — no crash, no
        // warning, and every size and weight in `WellieTheme` still tuned for a
        // typeface that is not on screen. That is the same shape of failure as
        // the month the Gemini schema stopped emitting weights: everything
        // works, and everything is wrong. So it is loud in development and
        // survivable in production, where a fallback face beats a crash.
        assert(
            WellieTheme.fontsAreInstalled,
            "Space Grotesk / IBM Plex Mono are missing from the bundle — check UIAppFonts in project.yml and re-run scripts/bootstrap.sh"
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.bootstrap() }
        }
    }
}

/// The app opens straight into the thread.
///
/// There is no tab bar any more, and no camera button in the middle of one. The
/// composer is always on screen, so a tab whose whole job was to open a capture
/// screen had nothing left to do — and `My week`, the only other destination,
/// is a link in the header where the mock puts it. Two tabs to reach two
/// screens was ceremony the moment logging stopped being a place you go.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if !model.hasBootstrapped {
            ProgressView()
                .tint(WellieTheme.blue)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(WellieTheme.ice.ignoresSafeArea())
        } else if !model.isSignedIn {
            SignInGateView()
                .transition(.opacity)
        // Onboarding follows identity. This is what makes an upgraded install
        // with an existing local log stop at Apple sign-in before any backend
        // work can resume under a shared credential.
        } else if model.hasOnboarded {
            LogThreadView()
                .tint(WellieTheme.blue)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.refreshHealth() }
                    // Polling on open, which is the whole of the freshness
                    // story until push exists. Every table response says when
                    // the server counted, so the row can draw its own age.
                    Task { await model.synchronizeAccount() }
                }
        } else {
            OnboardingView()
                .transition(.opacity)
        }
    }
}
