import ShamanCore
import SwiftUI

/// What opens when you tap a word in the sentence. Screen `2d`.
///
/// One question and a way out: is it this or one of those, and remove it.
///
/// The rivals are the model's own, and each arrives priced — so choosing one is
/// a whole answer, not half of one. That is the entire reason `alternatives`
/// carries a composition block: until v21 this sheet offered a picker over the
/// food taxonomy, and picking from it swapped what a food was *called* while a
/// table decided what it was worth. There is no table now, so a rename that
/// cannot restate the figures would leave a row whose numbers describe the food
/// it used to be — corrected-looking and wrong.
///
/// Anything not on the shortlist is therefore a correction in words, on the fix
/// screen, where `MealRefiner` re-prices what it renames. How much is shown and
/// not asked, for the same reason it has been since v17.
struct FoodEditSheet: View {
    @Binding var item: MealItem
    let onRemove: () -> Void
    var onChange: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 14) {
                        WellieSectionTitle(
                            text: "What is it?",
                            detail: item.alternatives.isEmpty
                                ? "The photo looked like \(item.label.lowercased()), and nothing else came close."
                                : "The photo looked like \(item.label.lowercased())."
                        )
                        FlowLayout(spacing: 7, lineSpacing: 7) {
                            WellieChip(text: item.label, style: .selected, size: 14)
                            ForEach(item.alternatives, id: \.label) { rival in
                                Button { choose(rival) } label: {
                                    WellieChip(text: rival.label, style: .soft, size: 14)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text("Something else? Say so on the fix screen — \"that was pork, not beef\" — and the figures move with the name.")
                            .font(WellieTheme.font(12, weight: .regular))
                            .foregroundStyle(WellieTheme.muted)
                    }
                    .wellieCard()

                    VStack(alignment: .leading, spacing: 10) {
                        WellieSectionTitle(text: "How much?", detail: weightDetail)
                        Text("\(Int(item.grams.rounded())) g")
                            .font(WellieTheme.font(22, weight: .bold))
                            .foregroundStyle(WellieTheme.ink)
                            .contentTransition(.numericText())
                        Text(energy)
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.muted)
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
            .navigationTitle(FoodPhrase.word(for: item).capitalizedFirst)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(WellieTheme.font(15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .wellieScreen()
    }

    private var weightDetail: String {
        "Read off the photo. Wrong? Say so on the fix screen — \"only half of that\"."
    }

    /// What this row contributes, so the weight above is not an abstraction.
    /// The only arithmetic on this screen, and it is `grams × per 100 g`.
    private var energy: String {
        "\(Int(item.nutrients.kcal.rounded())) kcal · \(Int(item.nutrients.protein.rounded())) g protein"
    }

    private func choose(_ rival: FoodAlternative) {
        item = item.choosing(rival)
        onChange?()
    }
}
