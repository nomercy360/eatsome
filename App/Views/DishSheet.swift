import ShamanCore
import SwiftUI

/// Screen `2d`. What is inside a dish, and how many of it there were.
///
/// The sentence names dishes because that is what a person recognises; this is
/// where the ingredients live, which is where a salmon filed as white meat gets
/// corrected. Hiding them entirely would hide the only mistake that matters —
/// a "kaisen don" scores wrong and looks right.
///
/// The two quantity controls get a row each. They shared one before, with a
/// second line of explanation stealing the width, and the three size chips wrapped
/// mid-word into "A litt le" against the edge of the card. A chip that wraps is a
/// chip that was never going to fit, so the subtitle went and the row is theirs.
struct DishSheet: View {
    let dish: MealDish
    let onRename: (String) -> Void
    let onEditIngredient: (UUID) -> Void
    let onAddIngredient: () -> Void
    let onCount: (Int) -> Void
    let onSize: (Portion) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var count: Int
    @State private var size: Portion
    @State private var isRenaming = false
    @State private var draftName: String

    init(
        dish: MealDish,
        onRename: @escaping (String) -> Void,
        onEditIngredient: @escaping (UUID) -> Void,
        onAddIngredient: @escaping () -> Void,
        onCount: @escaping (Int) -> Void,
        onSize: @escaping (Portion) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.dish = dish
        self.onRename = onRename
        self.onEditIngredient = onEditIngredient
        self.onAddIngredient = onAddIngredient
        self.onCount = onCount
        self.onSize = onSize
        self.onRemove = onRemove
        _count = State(initialValue: dish.count)
        _size = State(initialValue: dish.size)
        _draftName = State(initialValue: dish.name)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                quantityCard
                ingredientsCard

                Button("Remove this dish") {
                    onRemove()
                    dismiss()
                }
                .font(WellieTheme.font(15.5, weight: .semibold))
                .foregroundStyle(WellieTheme.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            // Not `wellieColumn`: that gives 6pt of top padding, which is right
            // under a navigation bar and far too tight under a drag indicator.
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 24)
            .padding(.bottom, 16)
        }
        .background(WellieTheme.background)
        .safeAreaInset(edge: .bottom) {
            Button("Done") { dismiss() }
                .buttonStyle(WelliePrimaryButtonStyle())
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(WellieTheme.background)
        }
        // Opens over the sentence rather than replacing it: the word you tapped
        // stays visible above, which is what makes this feel like opening a
        // word rather than navigating away from the meal. Taller than `.medium`
        // because at half the screen the last thing on the card — "Remove this
        // dish" — sits under the Done bar and reads as clipped rather than as
        // something to scroll to.
        // The sheet's own surface, not the system's. iOS draws Liquid Glass
        // behind a presented sheet, and a background on the content alone
        // leaves it showing in any gap the content does not fill — a tinted
        // band between the last control and the keyboard.
        .presentationBackground(WellieTheme.background)
        .presentationDetents([.fraction(0.74), .large])
        .presentationDragIndicator(.visible)
        .alert("Name this dish", isPresented: $isRenaming) {
            TextField("Kaisen don", text: $draftName)
            Button("Save") {
                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                onRename(trimmed)
            }
            Button("Cancel", role: .cancel) { draftName = dish.name }
        } message: {
            Text("What you'd call it out loud. This is the name it comes back under.")
        }
        .wellieScreen()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { isRenaming = true } label: {
                HStack(spacing: 9) {
                    Text(dish.name.isEmpty ? "Untitled dish" : dish.name)
                        .font(WellieTheme.font(21, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                        .multilineTextAlignment(.leading)
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WellieTheme.blue)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dish name, \(dish.name). Rename")

            Text(descriptor)
                .font(WellieTheme.font(13.5, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Sat hard against the sheet edge while every card below inset its own
        // contents, so the title read as belonging to the sheet rather than to
        // the dish. Nudged in toward the cards' inner margin.
        .padding(.horizontal, 10)
    }

    /// What kind of thing this is, and where it lands in the score. The second
    /// half is the only place the app says out loud that "Monster Energy zero
    /// sugar" is counted as a fizzy drink, which is the fact a person would
    /// otherwise have to open the ingredient row to discover.
    private var descriptor: String {
        var parts: [String] = []
        if dish.items.count == 1, let only = dish.items.first {
            parts.append(FoodPhrase.word(for: only.group, label: only.label).localizedCapitalized)
        } else if !dish.items.isEmpty {
            parts.append("\(dish.items.count) ingredients")
        }
        if let counts = groupSummary { parts.append("counts toward \(counts)") }
        let total = dish.items.compactMap(\.grams).reduce(0, +)
        if total > 0 { parts.insert("\(Int(total.rounded())) g", at: 0) }
        return parts.joined(separator: " · ")
    }

    private var groupSummary: String? {
        var seen: [FoodGroup] = []
        for item in dish.items where !seen.contains(item.group) { seen.append(item.group) }
        switch seen.count {
        case 0: return nil
        case 1: return seen[0].plainName.lowercased()
        case 2: return "\(seen[0].shortName.lowercased()) and \(seen[1].shortName.lowercased())"
        // Naming four groups makes a line nobody reads. The rows below say which.
        default: return "\(seen.count) food groups"
        }
    }

    private var quantityCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("How many?")
                        .font(WellieTheme.font(15.5, weight: .semibold))
                    Text(dish.weighed ? "Three cans is one dish, three times — this rescales the weights"
                                      : "Three cans is one dish, three times")
                        .font(WellieTheme.font(12.5, weight: .medium))
                        .foregroundStyle(WellieTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                stepper
            }
            .padding(.vertical, 13)

            if !dish.weighed {
            WellieRowDivider()

            HStack(spacing: 10) {
                Text("How big is one?")
                    .font(WellieTheme.font(15.5, weight: .semibold))
                    .fixedSize()
                Spacer(minLength: 6)
                // `fixedSize` on each chip is what keeps "A little" one word
                // wide. Without it the row shrinks them to fit and the text
                // wraps inside the pill instead of the row admitting it is full.
                HStack(spacing: 6) {
                    ForEach(Portion.allCases, id: \.self) { option in
                        Button {
                            size = option
                            onSize(option)
                        } label: {
                            WellieChip(
                                text: option.plainName,
                                style: size == option ? .selected : .soft
                            )
                            .fixedSize()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 13)
            }
        }
        .padding(.horizontal, 16)
        .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    /// Minus, the number, plus — one control rather than a label and a stepper
    /// at opposite ends of the row, so the number sits where it is changed.
    private var stepper: some View {
        HStack(spacing: 0) {
            stepperButton("minus", enabled: count > 1) { onCountChange(count - 1) }
            Text("\(count)")
                .font(WellieTheme.font(16, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
                .frame(minWidth: 26)
                .contentTransition(.numericText())
            stepperButton("plus", enabled: count < 24) { onCountChange(count + 1) }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(WellieTheme.background, in: Capsule())
        .overlay(Capsule().stroke(WellieTheme.ice, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("How many, \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if count < 24 { onCountChange(count + 1) }
            case .decrement: if count > 1 { onCountChange(count - 1) }
            @unknown default: break
            }
        }
    }

    private func stepperButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? WellieTheme.blue : WellieTheme.muted.opacity(0.5))
                .frame(width: 32, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func onCountChange(_ updated: Int) {
        withAnimation(.easeInOut(duration: 0.15)) { count = updated }
        onCount(updated)
    }

    private var ingredientsCard: some View {
        // Spacing 0: the rows carry their own padding, which is the contract a
        // list card is built on. Adding stack spacing on top of it is what made
        // four ingredients 250pt tall and pushed "Remove this dish" off screen.
        VStack(alignment: .leading, spacing: 0) {
            Text("WHAT'S IN IT")
                .font(WellieTheme.font(12, weight: .semibold))
                .foregroundStyle(WellieTheme.muted)
                .kerning(0.6)
                .padding(.top, 10)
                .padding(.bottom, 4)

            ForEach(dish.items) { item in
                Button {
                    dismiss()
                    onEditIngredient(item.id)
                } label: {
                    WellieChevronRow(
                        title: FoodPhrase.word(for: item.group, label: item.label),
                        // The weight where recognition estimated one. A gram
                        // figure and a size chip side by side would be two
                        // answers to one question, and only the weight scores.
                        value: item.grams.map { "\(Int($0.rounded())) g" } ?? item.portion.plainName,
                        verticalPadding: 9
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            // The photo misses what is under the sauce, and the correction
            // sheet only ever revises what is already listed. Without this the
            // only way to add a forgotten ingredient is to describe the whole
            // meal again.
            Button {
                dismiss()
                onAddIngredient()
            } label: {
                Label("Add an ingredient", systemImage: "plus")
                    .font(WellieTheme.font(15, weight: .semibold))
                    .foregroundStyle(WellieTheme.blue)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .wellieListCard()
    }
}
