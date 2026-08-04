import ShamanCore
import SwiftUI

@main
struct ShamanApp: App {
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

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.grid.2x2") }
            WorkoutSetupView()
                .tabItem { Label("Move", systemImage: "figure.strengthtraining.functional") }
            AdherenceView()
                .tabItem { Label("Diet", systemImage: "leaf") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
