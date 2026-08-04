import ShamanCore
import SwiftUI

struct AdherenceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let result = model.adherence()

        NavigationStack {
            List {
                Section { AdherenceSummaryRow(result: result) }

                Section("Where you stand") {
                    ForEach(result.items) { item in
                        MedasItemRow(item: item)
                    }
                }

                Section {
                    Text("""
                    Scored on the 14-item Mediterranean Diet Adherence Screener \
                    from the PREDIMED trial, over a rolling \(result.windowDays) days. \
                    Food-group frequency, not calories — that is what the screener \
                    measures and what a photograph can actually establish.
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Diet")
        }
    }
}

struct MedasItemRow: View {
    let item: MedasResult.ItemResult

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: item.passed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.passed ? .green : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var detail: String {
        // Habit items have no measurable quantity to report.
        guard item.id != 1, item.id != 13 else { return item.passed ? "Yes" : "No" }
        let observed = String(format: "%.1f", item.observed)
        let target = String(format: "%.0f", item.target)
        return item.isUpperBound ? "at \(observed), limit \(target)" : "at \(observed) of \(target)"
    }
}
