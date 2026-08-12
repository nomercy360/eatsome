import ShamanCore
import SwiftUI

/// What opens when you tap a word in the sentence.
///
/// One question and a way out: what is it, and remove it. The model's own
/// shortlist comes first, then the groups it habitually confuses, then
/// everything — so the likely answer is one tap and the unlikely one is still
/// reachable.
///
/// How much is shown and not asked. It was three chips until v17, and on a
/// weighed item they moved nothing — `effectiveServings` reads grams and never
/// reached the portion. Weight is corrected in words on the fix screen instead,
/// where "that was half a bowl" revises the number rather than picking a bucket
/// for it.
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
                            ForEach(shortlist, id: \.self) { kind in
                                Button { choose(kind) } label: {
                                    WellieChip(
                                        text: kind.plainName,
                                        style: kind == item.kind ? .selected : .soft,
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

                        TextField("Specific food name", text: label)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(WellieTheme.font(15, weight: .medium))
                            .foregroundStyle(WellieTheme.ink)
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 13))

                        Text("Use the actual food when you know it — for example soy sauce, mayonnaise, or teriyaki sauce.")
                            .font(WellieTheme.font(12, weight: .regular))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    .wellieCard()

                    VStack(alignment: .leading, spacing: 10) {
                        WellieSectionTitle(text: "How much?", detail: weightDetail)
                        Text(weight)
                            .font(WellieTheme.font(22, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .contentTransition(.numericText())
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
            .navigationTitle(FoodPhrase.word(for: item.kind, label: item.label).capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
            .sheet(isPresented: $showingEverything) {
                FoodKindPicker { choose($0) }
            }
        }
        .presentationDetents([.medium, .large])
        .wellieScreen()
    }

    /// What the photo was read as weighing. An item with no weight is either
    /// older than v17 or typed in by hand, and says so rather than showing a
    /// number nobody arrived at.
    private var weight: String {
        item.grams.map { "\(Int($0.rounded())) g" } ?? "Not weighed"
    }

    private var weightDetail: String {
        item.grams == nil
            ? "Added by hand. Say what it was on the fix screen and it gets a weight."
            : "Read off the photo. Wrong? Say so on the fix screen — \"only half of that\"."
    }

    private var label: Binding<String> {
        Binding(
            get: { item.label ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                item.label = trimmed.isEmpty ? nil : trimmed
                item.resolution = nil
                onChange?()
            }
        )
    }

    /// The model's rivals, then the ones it habitually confuses, then nothing
    /// else — the long tail lives behind "Something else".
    private var shortlist: [FoodKind] {
        var seen = Set<FoodKind>()
        let likely = [item.kind]
            + (item.modelAlternatives ?? []).map(\.kind)
            + item.kind.commonlyConfusedWith
        return likely.filter { seen.insert($0).inserted }
    }

    private func choose(_ kind: FoodKind) {
        guard kind != item.kind else { return }
        item.kind = kind
        // Once you have overruled the model, its shortlist was an answer to a
        // different question and should not be stored as evidence here.
        item.modelAlternatives = nil
        item.resolution = nil
        onChange?()
    }
}

/// Every group, with the plain name on the row and the group it counts as
/// underneath — the same pairing the by-hand screen uses, because it is the
/// same question.
struct FoodKindPicker: View {
    let onPick: (FoodKind) -> Void

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

    private var matches: [FoodKind] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return FoodKind.allCases }
        return FoodKind.allCases.filter {
            $0.plainName.lowercased().contains(needle) || $0.displayName.lowercased().contains(needle)
        }
    }
}
