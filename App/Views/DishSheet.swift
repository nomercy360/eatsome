import ShamanCore
import SwiftUI

/// What is inside a dish, and how many of it there were.
///
/// The sentence names dishes because that is what a person recognises; this is
/// where the ingredients live, which is where a salmon filed as white meat gets
/// corrected. Hiding them entirely would hide the only mistake that matters —
/// a "kaisen don" scores wrong and looks right.
struct DishSheet: View {
    let dish: MealDish
    let protein: Double
    let onEditIngredient: (UUID) -> Void
    let onCount: (Int) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var count: Int

    init(
        dish: MealDish,
        protein: Double,
        onEditIngredient: @escaping (UUID) -> Void,
        onCount: @escaping (Int) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.dish = dish
        self.protein = protein
        self.onEditIngredient = onEditIngredient
        self.onCount = onCount
        self.onRemove = onRemove
        _count = State(initialValue: dish.count)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: WellieTheme.cardSpacing) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("How many?")
                                .font(WellieTheme.font(15.5, weight: .semibold))
                            Spacer(minLength: 0)
                            Text("\(Int((protein * Double(count)).rounded())) g protein")
                                .font(WellieTheme.font(13, weight: .semibold))
                                .foregroundStyle(WellieTheme.muted)
                                .fixedSize()
                        }
                        Stepper(value: $count, in: 1...24) {
                            Text(count == 1 ? "One" : "\(count)")
                                .font(WellieTheme.font(17, weight: .bold))
                        }
                        .onChange(of: count) { _, updated in onCount(updated) }
                        WellieCaption("How many servings of this dish. Three beers is one dish, three times.")
                    }
                    .wellieCard(padding: 20)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("What's in it")
                            .font(WellieTheme.font(13, weight: .semibold))
                            .foregroundStyle(WellieTheme.muted)
                        ForEach(dish.items) { item in
                            Button {
                                dismiss()
                                onEditIngredient(item.id)
                            } label: {
                                WellieChevronRow(
                                    title: FoodPhrase.word(for: item.group, label: item.label),
                                    value: item.portion.plainName
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .wellieListCard()

                    Button("Remove this dish", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                    .font(WellieTheme.font(15.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.danger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .navigationTitle(dish.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .wellieScreen()
    }
}
