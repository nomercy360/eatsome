import ShamanCore
import SwiftUI

/// Screen `2f`. Earlier days.
///
/// There was no way to see yesterday in this app, which also meant no way to
/// add a meal you forgot. Days you did not log are shown rather than hidden: a
/// gap is information, and it is the one thing you can still fix.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var shown = 14
    @State private var capturing: DayLog?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(model.recentDays(shown)) { day in
                        DayCard(day: day) { capturing = day }
                    }

                    Button("Show more") { shown += 14 }
                        .buttonStyle(WellieQuietButtonStyle())
                        .padding(.top, 6)
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle("Earlier days")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
            .navigationDestination(for: DayLog.self) { DayView(day: $0.start) }
            .sheet(item: $capturing) { MealCaptureView(day: $0.start) }
        }
        .wellieScreen()
    }
}

private struct DayCard: View {
    @Environment(AppModel.self) private var model
    let day: DayLog
    let onAdd: () -> Void

    private var meals: [MealEntry] { model.meals(on: day.start) }

    var body: some View {
        VStack(alignment: .leading, spacing: meals.isEmpty ? 14 : 16) {
            NavigationLink(value: day) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(DayFormat.title(day.start))
                            .font(WellieTheme.font(17, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                        Text(summary)
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    Spacer(minLength: 8)
                    Circle()
                        .fill(day.fill > 0 ? WellieTheme.blue.opacity(0.25 + 0.75 * day.fill)
                                           : WellieTheme.blue.opacity(0.14))
                        .frame(width: 24, height: 24)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if meals.isEmpty {
                Button(action: onAdd) {
                    HStack(spacing: 12) {
                        Text("Remember what you ate? You can still add it.")
                            .font(WellieTheme.font(14.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.body)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Text("Add")
                            .font(WellieTheme.font(13.5, weight: .bold))
                            .foregroundStyle(WellieTheme.blue)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: WellieTheme.innerRadius, style: .continuous)
                            .strokeBorder(WellieTheme.outline, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Four slots always: the empty ones are how a quiet day looks
                // different from a full one at a glance.
                HStack(spacing: 9) {
                    ForEach(0..<4, id: \.self) { index in
                        if index < meals.count {
                            NavigationLink { MealDetailView(meal: meals[index]) } label: {
                                MealThumbnail(meal: meals[index], side: .infinity, radius: 16)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                            }
                            .buttonStyle(.plain)
                        } else {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(WellieTheme.well)
                                .aspectRatio(1, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }

                if !groups.isEmpty {
                    FlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(groups, id: \.self) { WellieChip(text: $0.plainName, size: 12.5) }
                    }
                }
            }
        }
        .wellieCard(padding: 20)
    }

    private var summary: String {
        guard !meals.isEmpty else { return "Nothing logged" }
        let count = Count.meals(meals.count).lowercased()
        switch meals.count {
        case 1: return "\(count.capitalizedFirst) · a quiet day"
        case 3...: return "\(count.capitalizedFirst) · a good day"
        default: return count.capitalizedFirst
        }
    }

    private var groups: [FoodGroup] {
        var seen = Set<FoodGroup>()
        return meals.flatMap(\.items).map(\.group).filter { seen.insert($0).inserted }
    }
}

/// One earlier day, opened from a dot or a history card.
struct DayView: View {
    let day: Date

    @Environment(AppModel.self) private var model
    @State private var capturing = false

    private var meals: [MealEntry] { model.meals(on: day) }

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                if meals.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        WellieSectionTitle(text: "Nothing logged")
                        WellieProse("A gap is information too. If you remember what you ate, it still counts.")
                        Button("Add a meal for this day") { capturing = true }
                            .buttonStyle(WellieSecondaryButtonStyle())
                    }
                    .wellieCard()
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(Count.meals(meals.count))
                            .font(WellieTheme.font(17, weight: .bold))
                        ForEach(meals) { meal in
                            NavigationLink { MealDetailView(meal: meal) } label: {
                                MealRow(meal: meal)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .wellieCard()

                    Button("Add another meal for this day") { capturing = true }
                        .buttonStyle(WellieQuietButtonStyle())
                }
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .navigationTitle(DayFormat.title(day))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $capturing) { MealCaptureView(day: day) }
        .wellieScreen()
    }
}
