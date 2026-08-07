import ShamanCore
import SwiftUI

/// Screen `2h`. What did you eat?
///
/// Plain names on the left, the group they count as underneath. Nothing about
/// the stored data changes — this is the same `FoodGroup` enum the model
/// answers in, wearing the words a person would use.
struct AddByHandView: View {
    /// Which day this lands on, so a meal remembered on Thursday can still be
    /// filed under Tuesday.
    var day: Date = Date()

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var picked: [MealItem] = []
    @State private var eatenAt = Date()
    @State private var editing: EditingFood?

    var body: some View {
        ScrollView {
            VStack(spacing: WellieTheme.cardSpacing) {
                if !picked.isEmpty { chosenCard }
                if query.isEmpty && !frequent.isEmpty { frequentCard }
                listCard

                WellieCaption("Plain names on the left, the group they count as underneath. Nothing about the stored data changes.")
                    .padding(.horizontal, 6)
            }
            .wellieColumn()
        }
        .background(WellieTheme.background)
        .searchable(text: $query, prompt: "Search foods")
        .navigationTitle("What did you eat?")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !picked.isEmpty {
                Button("Save this meal") { Task { await save() } }
                    .buttonStyle(WelliePrimaryButtonStyle())
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                    .background(WellieTheme.background)
            }
        }
        .sheet(item: $editing) { target in
            if let index = picked.firstIndex(where: { $0.id == target.id }) {
                FoodEditSheet(
                    item: $picked[index],
                    onRemove: { picked.removeAll { $0.id == target.id } }
                )
            }
        }
        .onAppear { eatenAt = startOfCapture(day) }
        .wellieScreen()
    }

    private var chosenCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tap a word to change how much")
                .font(WellieTheme.font(13, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
            FoodSentence(
                lead: "You had",
                words: picked.map { .init(id: $0.id, text: FoodPhrase.word(for: $0.group, label: $0.label)) },
                size: 21,
                onTap: { editing = EditingFood(id: $0) }
            )
        }
        .wellieCard()
    }

    /// What you actually add by hand, learned from the log rather than guessed.
    /// Olive oil and a handful of nuts are invisible to a camera and typed in
    /// constantly; the list should know that after a week.
    private var frequentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("You add these most")
                .font(WellieTheme.font(15, weight: .bold))
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(frequent, id: \.self) { group in
                    Button { add(group) } label: {
                        WellieChip(text: group.plainName, size: 14.5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .wellieCard(padding: 20)
    }

    private var listCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(matches.enumerated()), id: \.element) { index, group in
                Button { add(group) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.plainName)
                                .font(WellieTheme.font(16, weight: .semibold))
                                .foregroundStyle(WellieTheme.ink)
                            // Only where the two differ. "Olive oil / Olive
                            // oil" teaches nothing and makes the row look like
                            // a rendering bug.
                            if group.plainName != group.displayName {
                                Text(group.displayName)
                                    .font(WellieTheme.font(12.5, weight: .medium))
                                    .foregroundStyle(WellieTheme.muted)
                            }
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(WellieTheme.blue, WellieTheme.ice)
                    }
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < matches.count - 1 { WellieRowDivider() }
            }
        }
        .wellieListCard()
    }

    private var matches: [FoodGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return FoodGroup.allCases }
        return FoodGroup.allCases.filter {
            $0.plainName.lowercased().contains(needle) || $0.displayName.lowercased().contains(needle)
        }
    }

    /// What you actually type in, learned from the log. Until there is a log to
    /// learn from, the four a camera systematically cannot see: oil poured
    /// before the photo, a handful of nuts, fruit eaten standing up, and the
    /// vegetables buried in the dish.
    private var frequent: [FoodGroup] {
        var tally: [FoodGroup: Int] = [:]
        for meal in model.projection.meals.values where meal.source != .photo {
            for group in Set(meal.items.map(\.group)) { tally[group, default: 0] += 1 }
        }
        guard tally.count >= 4 else { return [.oliveOil, .nuts, .fruit, .vegetables] }
        return tally.sorted { $0.value > $1.value }.prefix(4).map(\.key)
    }

    private func add(_ group: FoodGroup) {
        picked.append(MealItem(group: group))
    }

    private func startOfCapture(_ day: Date) -> Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return Date() }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

    private func save() async {
        await model.logMeal(MealEntry(eatenAt: eatenAt.epochMillis, items: picked, source: .manual))
        dismiss()
    }
}
