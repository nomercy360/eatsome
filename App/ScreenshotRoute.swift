import ShamanCore
import SwiftUI

/// TEMPORARY — screenshot harness. Deleted before the change is finished.
struct ScreenshotRoute: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        switch name {
        case "week": NavigationStack { MyWeekView() }
        case "settings": SettingsView()
        case "history": HistoryView()
        case "capture": MealCaptureView()
        case "recipes": NavigationStack { RecipesView() }
        case "byhand": NavigationStack { AddByHandView() }
        case "method": ScoreMethodView()
        case "detail":
            if let meal = model.mealsToday().first {
                NavigationStack { MealDetailView(meal: meal) }
            } else {
                Text("no meals")
            }
        default: TodayView()
        }
    }
}
