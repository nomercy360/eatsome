import Charts
import ShamanCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCapture = false

    private var meals: [MealEntry] { model.mealsToday() }
    private var foodGroups: [FoodGroup] {
        var seen = Set<FoodGroup>()
        return meals.flatMap(\.items).map(\.group).filter { seen.insert($0).inserted }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    adherenceHero

                    if !foodGroups.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(foodGroups, id: \.self) { WellieChip(text: $0.displayName) }
                            }
                        }
                    }

                    Button {
                        showingCapture = true
                    } label: {
                        Label("Add meal", systemImage: "camera.fill")
                    }
                    .buttonStyle(WelliePrimaryButtonStyle())

                    mealsCard
                    healthCard

                    if let error = model.loadError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(WellieTheme.danger)
                            .wellieCard(color: WellieTheme.card)
                    }
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.bottom, 32)
            }
            .background(WellieTheme.background)
            .navigationTitle("EATSOME")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refreshHealth() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await model.refreshHealth() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh Health data")
                }
            }
            .sheet(isPresented: $showingCapture) { MealCaptureView() }
        }
        .wellieScreen()
    }

    private var adherenceHero: some View {
        let result = model.adherence()
        return NavigationLink {
            AdherenceView()
        } label: {
            VStack(spacing: 12) {
                Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(WellieTheme.font(14, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)

                WellieKicker(text: "Rolling adherence")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(result.score)")
                        .font(WellieTheme.font(64, weight: .bold))
                    Text("/ \(result.maxScore)")
                        .font(WellieTheme.font(28, weight: .bold))
                        .foregroundStyle(WellieTheme.muted)
                }

                Text(heroMessage(result))
                    .font(WellieTheme.font(16, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 330)

                ProgressView(value: Double(result.score), total: Double(max(result.maxScore, 1)))
                    .tint(WellieTheme.blue)

                if result.isUnderreported {
                    Text("Log meals on more days before treating this score as meaningful.")
                        .font(WellieTheme.font(12, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .wellieCard(color: WellieTheme.ice, padding: 24)
        }
        .buttonStyle(.plain)
    }

    private var mealsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                WellieKicker(text: "Today's meals")
                Spacer()
                Text("\(meals.count)")
                    .font(WellieTheme.font(13, weight: .bold))
                    .foregroundStyle(WellieTheme.blue)
            }
            .padding(.bottom, 8)

            if meals.isEmpty {
                Text("No meals logged yet. A photo is enough to begin.")
                    .font(WellieTheme.font(15, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .padding(.vertical, 14)
            } else {
                ForEach(Array(meals.enumerated()), id: \.element.id) { index, meal in
                    NavigationLink {
                        MealDetailView(meal: meal)
                    } label: {
                        MealHistoryRow(meal: meal)
                    }
                    .buttonStyle(.plain)

                    if index < meals.count - 1 { Divider() }
                }
            }
        }
        .wellieCard(color: WellieTheme.card)
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                WellieKicker(text: "From Apple Health")
                Spacer()
                if model.isLoadingHealth { ProgressView().controlSize(.small) }
            }

            if !model.hasRequestedHealthAccess
                && model.healthSnapshot.workouts.isEmpty
                && model.healthSnapshot.sleep.isEmpty
                && model.healthSnapshot.weights.isEmpty {
                Button("Connect Apple Health") { Task { await model.connectHealth() } }
                    .buttonStyle(WellieSecondaryButtonStyle())
            } else {
                HStack(alignment: .top, spacing: 10) {
                    HealthMetric(
                        icon: "moon.fill",
                        label: "Sleep",
                        value: model.latestSleep.map { duration($0.asleep) } ?? "—"
                    )
                    HealthMetric(
                        icon: "figure.run",
                        label: "Workout",
                        value: workoutValue
                    )
                    HealthMetric(
                        icon: "scalemass.fill",
                        label: "Weight",
                        value: model.latestWeight.map { WeightFormat.string($0.kilograms) } ?? "—"
                    )
                }

                if model.healthSnapshot.weights.count > 1 {
                    WeightTrendChart(measurements: model.healthSnapshot.weights)
                        .frame(height: 92)
                }
            }

            if let error = model.healthError {
                Text(error)
                    .font(WellieTheme.font(12, weight: .medium))
                    .foregroundStyle(WellieTheme.warningText)
            }
        }
        .wellieCard(color: WellieTheme.ice)
    }

    private var workoutValue: String {
        let seconds = model.workoutsToday().reduce(0) { $0 + $1.duration }
        return seconds > 0 ? duration(seconds) : "—"
    }

    private func heroMessage(_ result: MedasResult) -> String {
        if result.isUnderreported {
            return "A few consistent days will reveal your Mediterranean pattern."
        }
        return result.meetsGoodAdherence
            ? "Your seven-day pattern is on track. Keep the rhythm gentle and steady."
            : "Your week is taking shape. The detail view shows the easiest next step."
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}

private struct MealHistoryRow: View {
    let meal: MealEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: meal.source == .photo ? "camera.fill" : "fork.knife")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(WellieTheme.blue)
                .frame(width: 38, height: 38)
                .background(WellieTheme.softBlue, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(MealDisplay.title(meal))
                    .font(WellieTheme.font(16, weight: .semibold))
                    .lineLimit(1)
                Text(MealDisplay.subtitle(meal))
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Text(Date(epochMillis: meal.eatenAt).formatted(date: .omitted, time: .shortened))
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
        .padding(.vertical, 10)
    }
}

private struct HealthMetric: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(WellieTheme.blue)
            Text(label)
                .font(WellieTheme.font(12, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
            Text(value)
                .font(WellieTheme.font(15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(WellieTheme.elevated.opacity(0.82), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct WeightTrendChart: View {
    let measurements: [WeightMeasurement]

    private var recent: [WeightMeasurement] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? .distantPast
        return measurements.filter { $0.measuredAt >= cutoff }.sorted { $0.measuredAt < $1.measuredAt }
    }

    var body: some View {
        Chart(recent) { measurement in
            LineMark(
                x: .value("Date", measurement.measuredAt),
                y: .value("Weight", WeightFormat.value(measurement.kilograms))
            )
            .foregroundStyle(WellieTheme.blue)
            .interpolationMethod(.catmullRom)
            PointMark(
                x: .value("Date", measurement.measuredAt),
                y: .value("Weight", WeightFormat.value(measurement.kilograms))
            )
            .foregroundStyle(WellieTheme.blue)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                    .foregroundStyle(WellieTheme.muted)
            }
        }
    }
}

enum MealDisplay {
    static func title(_ meal: MealEntry) -> String {
        let labels = meal.items.compactMap(\.label).filter { !$0.isEmpty }
        if !labels.isEmpty { return labels.prefix(3).joined(separator: ", ") }
        let groups = uniqueGroups(meal)
        return groups.isEmpty ? "Meal" : groups.prefix(3).map(\.displayName).joined(separator: ", ")
    }

    static func subtitle(_ meal: MealEntry) -> String {
        let groups = uniqueGroups(meal).prefix(4).map(\.displayName).joined(separator: " · ")
        // A half-counted meal looks identical to a whole one in the list
        // otherwise, and the difference is the whole point of the switch.
        return meal.eaten == .part ? "\(groups) · ate part" : groups
    }

    private static func uniqueGroups(_ meal: MealEntry) -> [FoodGroup] {
        var seen = Set<FoodGroup>()
        return meal.items.map(\.group).filter { seen.insert($0).inserted }
    }
}

enum WeightFormat {
    static var usesMetric: Bool { Locale.current.measurementSystem == .metric }
    static var unit: String { usesMetric ? "kg" : "lb" }

    static func value(_ kilograms: Double) -> Double {
        usesMetric ? kilograms : kilograms * 2.204_622_621_8
    }

    static func string(_ kilograms: Double) -> String {
        "\(value(kilograms).formatted(.number.precision(.fractionLength(1)))) \(unit)"
    }
}
