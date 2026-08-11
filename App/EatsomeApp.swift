import ShamanCore
import SwiftUI

@main
struct EatsomeApp: App {
    @State private var model = AppModel()

    init() {
        // The identity is Sora, bundled, in five cuts. If any of them ever falls
        // out of the target's resources, `UIFont(name:)` returns nil and SwiftUI
        // quietly renders the system face instead — no crash, no warning, and
        // every size and weight in `WellieTheme` still tuned for a typeface that
        // is not on screen. That is the same shape of failure as the month the
        // Gemini schema stopped emitting weights: everything works, and
        // everything is wrong. So it is loud in development and survivable in
        // production, where a fallback face beats a crash.
        assert(
            WellieTheme.fontsAreInstalled,
            "Sora is missing from the bundle — check UIAppFonts in project.yml, re-run scripts/build-fonts.py, and re-run scripts/bootstrap.sh"
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                // The redesign is one scheme, and it is the dark one. Not "has
                // a dark mode": every surface, every contrast ratio and the one
                // translucent card on the meal detail were drawn against
                // `#0b0d12`. Following the system here would hand half the
                // users a light app nobody designed, where `faint` on white is
                // 1.6:1 and the whole page disappears.
                .preferredColorScheme(.dark)
                .task { await model.bootstrap() }
                .onOpenURL { model.handleIncomingURL($0) }
        }
    }
}

/// The app opens on the four-place shell.
///
/// Today, Tables, Progress, and You are durable destinations. Logging remains a
/// sheet because it is an action rather than a place, opened from the separate
/// `+` beside the tabs.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.hasBootstrapped {
                ProgressView()
                    .tint(WellieTheme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(WellieTheme.background.ignoresSafeArea())
            } else if !model.isSignedIn {
                SignInGateView()
                    .transition(.opacity)
            // Onboarding follows identity. This is what makes an upgraded install
            // with an existing local log stop at Apple sign-in before any backend
            // work can resume under a shared credential.
            } else if model.hasOnboarded {
                MainTabView()
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: inviteSheetPresented) {
            if let code = model.pendingTableInviteCode {
                TableInviteJoinSheet(inviteCode: code)
            }
        }
    }

    /// Keep a link opened during sign-in or the required onboarding migration
    /// pending. The confirmation appears only after the person has a backend
    /// identity and the current profile is complete.
    private var inviteSheetPresented: Binding<Bool> {
        Binding(
            get: {
                model.isSignedIn
                    && model.hasOnboarded
                    && model.pendingTableInviteCode != nil
            },
            set: { shown in
                if !shown { model.clearPendingTableInvite() }
            }
        )
    }
}
