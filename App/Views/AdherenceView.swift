import ShamanCore
import SwiftUI

struct AdherenceView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let result = model.adherence()

        ScrollView {
            LazyVStack(spacing: 18) {
                scoreHero(result)

                VStack(alignment: .leading, spacing: 18) {
                    WellieKicker(text: "Build through the week")
                    ForEach(buildItems(result)) { TargetProgressRow(item: $0) }
                }
                .wellieCard(color: WellieTheme.card)

                VStack(alignment: .leading, spacing: 14) {
                    WellieKicker(text: "Stay under")
                    ForEach(limitItems(result)) { LimitRow(item: $0) }
                }
                .wellieCard(color: WellieTheme.ice)

                VStack(alignment: .leading, spacing: 14) {
                    WellieKicker(text: "Your habits")
                    ForEach(habitItems(result)) { HabitRow(item: $0) }
                }
                .wellieCard(color: WellieTheme.card)

                Text("Based on the Mediterranean Diet Adherence Screener from the PREDIMED trial, measured over a rolling \(result.windowDays)-day window. Food-group frequency—not calories—is the signal.")
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.bottom, 32)
        }
        .navigationTitle("My week")
        .navigationBarTitleDisplayMode(.inline)
        .wellieScreen()
    }

    private func scoreHero(_ result: MedasResult) -> some View {
        VStack(spacing: 10) {
            WellieKicker(text: "Mediterranean adherence")
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(result.score)")
                    .font(WellieTheme.font(64, weight: .bold))
                Text("/ \(result.maxScore)")
                    .font(WellieTheme.font(28, weight: .bold))
                    .foregroundStyle(WellieTheme.muted)
            }
            Text(result.meetsGoodAdherence ? "Your rolling pattern is on track." : "Every logged meal makes the next step clearer.")
                .font(WellieTheme.font(16, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
                .multilineTextAlignment(.center)
            if result.isUnderreported {
                Label("Only \(result.daysLogged) of \(result.windowDays) days logged", systemImage: "exclamationmark.triangle.fill")
                    .font(WellieTheme.font(12, weight: .semibold))
                    .foregroundStyle(WellieTheme.warningText)
            }
        }
        .frame(maxWidth: .infinity)
        .wellieCard(color: WellieTheme.ice, padding: 26)
    }

    private func buildItems(_ result: MedasResult) -> [MedasResult.ItemResult] {
        result.items.filter { !$0.isUpperBound && $0.id != 1 && $0.id != 13 }
    }

    private func limitItems(_ result: MedasResult) -> [MedasResult.ItemResult] {
        result.items.filter(\.isUpperBound)
    }

    private func habitItems(_ result: MedasResult) -> [MedasResult.ItemResult] {
        result.items.filter { $0.id == 1 || $0.id == 13 }
    }
}

private struct TargetProgressRow: View {
    let item: MedasResult.ItemResult

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(shortTitle)
                    .font(WellieTheme.font(15, weight: .semibold))
                Spacer()
                Text("\(item.observed.formatted(.number.precision(.fractionLength(1)))) / \(item.target.formatted(.number.precision(.fractionLength(0))))")
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }
            ProgressView(value: min(item.observed, item.target), total: max(item.target, 0.01))
                .tint(item.passed ? WellieTheme.blue : WellieTheme.muted)
        }
    }

    private var shortTitle: String { item.title.components(separatedBy: " ≥").first ?? item.title }
}

private struct LimitRow: View {
    let item: MedasResult.ItemResult

    var body: some View {
        HStack {
            Image(systemName: item.passed ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(item.passed ? WellieTheme.blue : WellieTheme.warningText)
            Text(item.title.components(separatedBy: " <").first ?? item.title)
                .font(WellieTheme.font(15, weight: .semibold))
            Spacer()
            Text("\(item.observed.formatted(.number.precision(.fractionLength(1)))) of \(item.target.formatted(.number.precision(.fractionLength(0))))")
                .font(WellieTheme.font(13, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
    }
}

private struct HabitRow: View {
    let item: MedasResult.ItemResult

    var body: some View {
        HStack {
            Image(systemName: item.passed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(item.passed ? WellieTheme.blue : WellieTheme.muted)
            Text(item.title)
                .font(WellieTheme.font(15, weight: .semibold))
        }
    }
}
