import ShamanCore
import SwiftUI

@main
struct EatsomeApp: App {
    @State private var model = AppModel()

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
        // Four onboarding screens, each asking for exactly one thing, and every
        // ask skippable. They explain before iOS does, so a refusal is a
        // decision rather than permanent confusion.
        if model.hasOnboarded {
            LogThreadView()
                .tint(WellieTheme.blue)
                .fontDesign(.rounded)
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.refreshHealth() }
                }
        } else {
            OnboardingView()
                .transition(.opacity)
        }
    }
}
