import ShamanCore
import SwiftUI

/// What opens when you tap a word in the sentence.
///
/// Two questions and a way out, in the order they matter: what is it, how much
/// was there, and remove it. The model's own shortlist comes first, then the
/// groups it habitually confuses, then everything — so the likely answer is
/// one tap and the unlikely one is still reachable.
struct FoodEditSheet: View {
    @Binding var item: MealItem
    let onRemove: () -> Void
    var onChange: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showingEverything = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 14) {
                        WellieSectionTitle(
                            text: "What is it?",
                            detail: item.label.map { "The photo looked like \($0.lowercased())." }
                        )
                        FlowLayout(spacing: 7, lineSpacing: 7) {
                            ForEach(shortlist, id: \.self) { group in
                                Button { choose(group) } label: {
                                    WellieChip(
                                        text: group.plainName,
                                        style: group == item.group ? .selected : .soft,
                                        size: 14
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            Button { showingEverything = true } label: {
                                WellieChip(text: "Something else", style: .outline, size: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .wellieCard()

                    VStack(alignment: .leading, spacing: 14) {
                        WellieSectionTitle(text: "How much?", detail: "Rough is fine — nothing here is weighed.")
                        HStack(spacing: 7) {
                            ForEach(Portion.allCases, id: \.self) { portion in
                                Button {
                                    item.portion = portion
                                    onChange?()
                                } label: {
                                    WellieChip(
                                        text: portion.plainName,
                                        style: portion == item.portion ? .selected : .soft,
                                        size: 14
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .wellieCard()

                    Button(role: .destructive) {
                        onRemove()
                        dismiss()
                    } label: {
                        Text("Remove this")
                            .font(WellieTheme.font(15.5, weight: .semibold))
                            .foregroundStyle(WellieTheme.danger)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle(FoodPhrase.word(for: item.group, label: item.label).capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
            .sheet(isPresented: $showingEverything) {
                FoodGroupPicker { choose($0) }
            }
        }
        .presentationDetents([.medium, .large])
        .wellieScreen()
    }

    /// The model's rivals, then the ones it habitually confuses, then nothing
    /// else — the long tail lives behind "Something else".
    private var shortlist: [FoodGroup] {
        var seen = Set<FoodGroup>()
        let likely = [item.group]
            + (item.modelAlternatives ?? [])
            + item.group.commonlyConfusedWith
        return likely.filter { seen.insert($0).inserted }
    }

    private func choose(_ group: FoodGroup) {
        guard group != item.group else { return }
        item.group = group
        // Once you have overruled the model, its shortlist was an answer to a
        // different question and should not be stored as evidence here.
        item.modelAlternatives = nil
        onChange?()
    }
}

/// Every group, with the plain name on the row and the group it counts as
/// underneath — the same pairing the by-hand screen uses, because it is the
/// same question.
struct FoodGroupPicker: View {
    let onPick: (FoodGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(matches.enumerated()), id: \.element) { index, group in
                        Button {
                            onPick(group)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.plainName)
                                        .font(WellieTheme.font(16, weight: .semibold))
                                        .foregroundStyle(WellieTheme.ink)
                                    Text(group.displayName)
                                        .font(WellieTheme.font(12.5, weight: .medium))
                                        .foregroundStyle(WellieTheme.muted)
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
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 6)
            }
            .background(WellieTheme.background)
            .searchable(text: $query, prompt: "Search foods")
            .navigationTitle("Every food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .wellieScreen()
    }

    private var matches: [FoodGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return FoodGroup.allCases }
        return FoodGroup.allCases.filter {
            $0.plainName.lowercased().contains(needle) || $0.displayName.lowercased().contains(needle)
        }
    }
}
