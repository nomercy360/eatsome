import EatsomeCore
import SwiftUI

// The controls a meal is corrected with, in place: how much of it was yours,
// how many there were, what size it was, which one it was. Every one of them
// moves a stored, priced value, so the figures above them are never a name
// with the old numbers behind it.

/// An option this row is currently set to, among ones you could still tap.
///
/// One chip, not three. The share row, the size row and the which-one row each
/// wrote this out, and the copies had already drifted: two drew an unselected
/// edge in `hairline` and the third in `outline`, and only one thickened the
/// edge on selection. Unified on the pair that reads: `hairline` because these
/// chips *have* a fill and `outline` is for a control that does not, and 1.5 pt
/// when selected because the wash alone is deliberately quiet enough that the
/// figures above stay the loudest thing on the card.
struct PickChip: View {
    let text: String
    let selected: Bool
    var size: CGFloat = 14
    /// Take the whole width offered rather than hugging the words.
    var fills = false
    /// Take the whole height offered. The share row sizes its chips against the
    /// stepper beside them rather than against their own text.
    var expands = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(WellieTheme.font(size, weight: selected ? .bold : .semibold))
                .foregroundStyle(selected ? WellieTheme.ink : WellieTheme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .frame(
                    maxWidth: fills ? .infinity : nil,
                    maxHeight: expands ? .infinity : nil
                )
                .wellieSurface(
                    selected ? WellieTheme.selectedFill : WellieTheme.surface,
                    radius: WellieTheme.chipRadius,
                    border: selected ? WellieTheme.accent : WellieTheme.hairline,
                    lineWidth: selected ? 1.5 : 1
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// `[A taste] [Half] [− All of it +]`.
///
/// Three chips and a stepper in one row: the two on the left are fractions of
/// the whole, the one on the right is the whole and how many of it. Selecting
/// a fraction sets the share; the `+` adds a whole one and clears the share,
/// because "half of four" is not something anyone says about four cartons.
struct ShareAndCountRow: View {
    @Binding var share: MealShare?
    @Binding var count: Int
    /// "All of it" at count 1, "× 4" above.
    var body: some View {
        // flex 1 : 1 : 2, as drawn. A priority-based layout let the stepper
        // swallow the row once its label grew to "× 4".
        GeometryReader { geometry in
            let unit = (geometry.size.width - 16) / 4
            HStack(spacing: 8) {
                chip(.taste).frame(width: unit)
                chip(.part).frame(width: unit)
                stepper.frame(width: unit * 2)
            }
        }
        .frame(height: 46)
    }

    private func chip(_ option: MealShare) -> some View {
        PickChip(
            text: option.chipName,
            selected: share == option,
            fills: true,
            expands: true
        ) { share = option }
    }

    private var whole: Bool { (share ?? .whole) == .whole }

    private var stepper: some View {
        HStack(spacing: 0) {
            StepButton(symbol: "minus", enabled: count > 1) {
                count = max(1, count - 1)
            }
            Text(count > 1 ? "× \(count)" : "All of it")
                .font(WellieTheme.font(count > 1 ? 16 : 13.5, weight: count > 1 ? .heavy : .bold))
                .foregroundStyle(WellieTheme.ink)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .contentShape(Rectangle())
                .onTapGesture { share = nil }
            StepButton(symbol: "plus", enabled: count < 24) {
                count = min(24, count + 1)
                share = nil
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .wellieSurface(whole ? WellieTheme.selectedFill : WellieTheme.surface, radius: 16, border: whole ? WellieTheme.accent : WellieTheme.hairline, lineWidth: whole ? 1.5 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(count > 1 ? "\(count) servings" : "All of it")
    }
}

/// `−` / `+`, 34 wide, faint when it can't go further.
struct StepButton: View {
    let symbol: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(enabled ? WellieTheme.accent : WellieTheme.faint)
                .frame(width: 34)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Add one" : "Remove one")
    }
}

/// The compact stepper in a mixed meal's list row: `raised` pill, count in the
/// middle. Same rules as the big one, smaller.
struct RowStepper: View {
    @Binding var count: Int

    var body: some View {
        HStack(spacing: 0) {
            StepButton(symbol: "minus", enabled: count > 1) { count = max(1, count - 1) }
            Text("\(count)")
                .font(WellieTheme.font(15, weight: .heavy))
                .foregroundStyle(WellieTheme.ink)
                .frame(minWidth: 24)
                .monospacedDigit()
            StepButton(symbol: "plus", enabled: count < 24) { count = min(24, count + 1) }
        }
        .frame(height: 36)
        .background(WellieTheme.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count) servings")
    }
}

/// `WHAT SIZE?` — one chip per size the chain sells, each priced in full.
struct SizeChips: View {
    let sizes: [FoodSize]
    @Binding var selection: FoodSize?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WellieMeta("What size?", size: 11.5)
            HStack(spacing: 8) {
                ForEach(sizes) { size in
                    PickChip(
                        text: size.label,
                        selected: selection?.id == size.id,
                        fills: true
                    ) { selection = size }
                }
            }
        }
    }
}

/// `WHICH ONE?` — the item as named, then each priced rival. Wrapping.
struct WhichOneChips: View {
    let current: String
    let alternatives: [FoodAlternative]
    /// Nil means the item as first named.
    @Binding var selection: FoodAlternative?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WellieMeta("Which one?", size: 11.5)
            FlowLayout(spacing: 8, lineSpacing: 8) {
                PickChip(
                    text: EatsomeFormat.capitalizedFirst(current),
                    selected: selection == nil,
                    size: 13.5
                ) { selection = nil }
                ForEach(alternatives) { rival in
                    PickChip(
                        text: EatsomeFormat.capitalizedFirst(rival.label),
                        selected: selection?.id == rival.id,
                        size: 13.5
                    ) { selection = rival }
                }
            }
        }
    }
}


// MARK: - The sheets

/// Frames 4 and 9: change the pick for one dish, with a live preview of what
/// that dish then contributes, and one button.
///
/// The preview is the whole contribution — count included — because that is
/// the number that will move on the card, and a per-unit figure beside a
/// count is arithmetic the person would have to do in their head. It
/// recomputes from the chosen `FoodSize` / `FoodAlternative`, both priced,
/// which is what "re-prices by construction" means.
struct ChangePickSheet: View {
    let dish: MealDish
    /// Frame 9 shows the share and count controls too; frame 4 does not.
    var showsAmount = false
    /// The dish's own share, for a mixed meal. Ignored when `showsAmount` is off.
    var share: MealShare? = nil
    let onUse: (MealDish, MealShare?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var count: Int
    @State private var pickedShare: MealShare?
    @State private var size: FoodSize?
    @State private var alternative: FoodAlternative?

    init(dish: MealDish, showsAmount: Bool = false, share: MealShare? = nil, onUse: @escaping (MealDish, MealShare?) -> Void) {
        self.dish = dish
        self.showsAmount = showsAmount
        self.share = share
        self.onUse = onUse
        _count = State(initialValue: dish.count)
        _pickedShare = State(initialValue: share)
        _size = State(initialValue: dish.items.first.flatMap { MealDetailModel.chosenSize(of: $0, count: dish.count) })
        _alternative = State(initialValue: nil)
    }

    private var item: MealItem? { dish.items.first }

    private var preview: MealDish {
        var next = MealDetailModel.applying(count: count, size: size, alternative: alternative, to: dish)
        next.share = showsAmount && pickedShare != .whole ? pickedShare : nil
        return next
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(showsAmount ? (dish.name.map(EatsomeFormat.capitalizedFirst) ?? "This item") : "Change the pick")
                    .font(WellieTheme.font(17, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") { dismiss() }
                    .font(WellieTheme.font(14, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
            }
            .padding(.top, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if showsAmount {
                        VStack(alignment: .leading, spacing: 10) {
                            WellieMeta("How much?", size: 11.5)
                            ShareAndCountRow(share: $pickedShare, count: $count)
                        }
                    }
                    if let item, item.sizes.count > 1 {
                        SizeChips(sizes: item.sizes, selection: $size)
                    }
                    if let item, !item.alternatives.isEmpty {
                        WhichOneChips(current: item.label, alternatives: item.alternatives, selection: $alternative)
                    }
                    previewRow
                }
                .padding(.top, 20)
            }
            .scrollIndicators(.hidden)

            Button {
                onUse(preview, showsAmount ? pickedShare : nil)
                dismiss()
            } label: {
                Text("Use this")
                    .font(WellieTheme.font(15, weight: .bold))
                    .foregroundStyle(WellieTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(WellieTheme.accent, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .background(WellieTheme.background)
        .wellieScreen()
    }

    private var previewRow: some View {
        VStack(spacing: 0) {
            Rectangle().fill(WellieTheme.hairline).frame(height: 1)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(previewDescription)
                    .font(WellieTheme.font(12.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text("\(EatsomeFormat.whole(preview.nutrients.kcal)) kcal")
                    .font(WellieTheme.font(13, weight: .bold))
                    .foregroundStyle(WellieTheme.body)
            }
            .padding(.top, 14)
        }
        .accessibilityElement(children: .combine)
    }

    private var previewDescription: String {
        guard let item = preview.items.first else { return "" }
        var text = EatsomeFormat.capitalizedFirst(item.label)
        if let size { text += ", \(size.label)" }
        if count > 1 { text += " × \(count)" }
        if showsAmount, let pickedShare, pickedShare != .whole { text += " · \(pickedShare.chipName.lowercased())" }
        return text
    }
}
