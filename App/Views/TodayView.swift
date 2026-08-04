import ShamanCore
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var showingCapture = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    let result = model.adherence()
                    NavigationLink {
                        AdherenceView()
                    } label: {
                        AdherenceSummaryRow(result: result)
                    }
                } header: {
                    Text("This week")
                }

                Section("Movement") {
                    LabeledContent("Today") {
                        Text(model.movedToday ? "Done" : "Not yet")
                            .foregroundStyle(model.movedToday ? .green : .secondary)
                    }
                    LabeledContent("Streak") {
                        Text("\(model.movementStreak()) days")
                    }
                    ForEach(model.setsToday()) { record in
                        LabeledContent(record.movementID) {
                            Text(record.holdSeconds.map { "\(Int($0))s" } ?? "\(record.reps) reps")
                                .monospacedDigit()
                        }
                    }
                }

                if let error = model.loadError {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                Button {
                    showingCapture = true
                } label: {
                    Label("Log a meal", systemImage: "camera")
                }
            }
            .sheet(isPresented: $showingCapture) { MealCaptureView() }
        }
    }
}

struct AdherenceSummaryRow: View {
    let result: MedasResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(result.score)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("of \(result.maxScore)")
                    .foregroundStyle(.secondary)
                Spacer()
                if result.meetsGoodAdherence {
                    Text("On track").font(.subheadline).foregroundStyle(.green)
                }
            }
            ProgressView(value: Double(result.score), total: Double(max(result.maxScore, 1)))
            if result.isUnderreported {
                // Never let a high score stand unqualified on two logged meals.
                Label(
                    "Only \(result.daysLogged) of \(result.windowDays) days logged — the score is not meaningful yet.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
