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

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: RootTab = .today
    @State private var isCapturing = false

    private enum RootTab: Hashable { case today, camera, week }

    /// Camera is a button wearing a tab's clothes. Selecting it opens the capture
    /// sheet and leaves `tab` where it was, so the bar never switches to a screen
    /// that does not exist. A real middle tab is what buys the system tab bar —
    /// glass, minimise-on-scroll, accessibility — instead of a floating button
    /// drawn on top of it. The price is a flat unaccented icon, which is the
    /// trade being made deliberately.
    private var selection: Binding<RootTab> {
        Binding(
            get: { tab },
            set: { next in
                guard next != .camera else {
                    isCapturing = true
                    return
                }
                tab = next
            }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            TodayView()
                .tag(RootTab.today)
                .tabItem { Label("Today", systemImage: "house.fill") }

            // Never rendered: the binding above intercepts the selection before
            // this can become the active tab.
            Color.clear
                .tag(RootTab.camera)
                .tabItem { Label("Camera", systemImage: "camera.fill") }

            NavigationStack { AdherenceView() }
                .tag(RootTab.week)
                // The mock draws six dots in a 3×2 grid; SF Symbols has no
                // circle.grid.3x2, and an invalid name renders as nothing at all.
                .tabItem { Label("My week", systemImage: "circle.grid.3x3.fill") }
        }
        .tint(WellieTheme.blue)
        .fontDesign(.rounded)
        // Presented from the root so the sheet covers the tab bar whichever tab
        // the tap came from.
        .sheet(isPresented: $isCapturing) { MealCaptureView() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshHealth() }
        }
    }
}
