import ShamanCore
import SwiftUI

/// What the app saw, written as a sentence you can tap a word in.
///
/// A list of rows with a picker on each says "here is a form, fill it in". The
/// same facts as a sentence say "here is what I think you ate" — and reading it
/// is the check. Most meals need no correction at all, and a sentence lets you
/// confirm one at a glance instead of scanning three controls per food.
///
/// The tap target is the word itself. That is the whole interaction: no edit
/// mode, no row to find, no chevron to discover.
struct FoodSentence: View {
    struct Word: Identifiable {
        let id: UUID
        let text: String
        /// Drawn with an underline: the model named a rival for this one that
        /// would change the meal reading, and the question is asked below.
        var isUncertain = false
        /// Not a word yet — a placeholder for what a fix is about to add.
        ///
        /// The point of the ghost is that the rest of the sentence does not
        /// move: your confirmed words stay exactly where they were while the
        /// model works, and only this one is unsettled. Blanking the sentence
        /// and rebuilding it is what makes a correction feel like it threw
        /// your work away.
        var isPending = false
    }

    let lead: String
    let words: [Word]
    var size: CGFloat = 23
    /// Commas, "and", and the full stop at the end.
    ///
    /// True where the sentence is prose — the capture screen's "You had *toast,
    /// eggs and coffee.*" False where it stands in for a title, which is what
    /// the meal detail does with it: a heading that ends in a full stop reads as
    /// a typo, and with one dish it produced "Lentil soup ." under the photo.
    /// The "and" survives either way; that is grammar, not punctuation.
    var punctuates = true
    var onTap: ((UUID) -> Void)?

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 9) {
            if !lead.isEmpty { plain(lead) }

            ForEach(Array(words.enumerated()), id: \.element.id) { index, word in
                // A Group is flattened into separate subviews by the layout, so
                // "and" wraps as its own word rather than gluing to the chip.
                Group {
                    if index > 0, index == words.count - 1 { plain("and") }
                    token(word, joiner: joiner(after: index))
                }
            }
        }
    }

    /// The chip and the punctuation that follows it are one view, so a comma
    /// can never wrap onto the next line on its own.
    private func token(_ word: Word, joiner: String) -> some View {
        HStack(spacing: 0) {
            Button { onTap?(word.id) } label: {
                Text(word.text)
                    .font(WellieTheme.font(size, weight: .semibold))
                    .foregroundStyle(word.isPending ? WellieTheme.muted : WellieTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(WellieTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .opacity(word.isPending ? 0.55 : 1)
                    .overlay(alignment: .bottom) {
                        if word.isUncertain {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(WellieTheme.accent)
                                .frame(height: 2)
                                .padding(.horizontal, 8)
                                .offset(y: 1)
                        }
                    }
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil || word.isPending)
            .accessibilityLabel(accessibilityLabel(for: word))
            .accessibilityHint(onTap == nil || word.isPending ? "" : "Change what this is")

            if !joiner.isEmpty { plain(joiner) }
        }
    }

    private func accessibilityLabel(for word: Word) -> String {
        if word.isPending { return "Working in your fix" }
        return word.isUncertain ? "\(word.text), unsure" : word.text
    }

    private func plain(_ text: String) -> some View {
        Text(text)
            .font(WellieTheme.font(size, weight: .semibold))
            .foregroundStyle(WellieTheme.ink)
    }

    /// English list punctuation: commas between, "and" before the last, a full
    /// stop at the end.
    private func joiner(after index: Int) -> String {
        guard punctuates else { return "" }
        switch words.count - index {
        case 1: return "."
        case 2: return ""
        default: return ","
        }
    }
}

extension FoodSentence {
    /// The sentence for a plate of dishes, in one place because two screens
    /// draw it and a rule that lives in both is a rule that will differ in one.
    ///
    /// A dish is normally one word with its ingredients behind it. The
    /// exception is the dish `MealDish.regrouped` builds for food a correction
    /// added: it has no name, because guessing which dish a new food joined
    /// would silently change that dish's count. Rendering its empty name put a
    /// blank chip in the middle of the sentence — "Looks like ramen and ." —
    /// after a fix that had worked perfectly. Those foods are said one by one
    /// instead, which also means tapping one opens the food rather than a dish
    /// sheet titled "Untitled dish".
    static func words(for dishes: [MealDish], uncertain: Set<UUID> = []) -> [Word] {
        dishes.flatMap { dish -> [Word] in
            let name = (dish.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                return dish.items.map { item in
                    Word(
                        id: item.id,
                        text: FoodPhrase.word(for: item),
                        isUncertain: uncertain.contains(item.id)
                    )
                }
            }
            return [
                Word(
                    id: dish.id,
                    text: dish.count > 1 ? "\(dish.count) × \(name)" : name,
                    // The question is about an ingredient, so the dish holding
                    // it is what carries the mark.
                    isUncertain: dish.items.contains { uncertain.contains($0.id) }
                )
            ]
        }
    }
}

/// Builds the sentence's words from what the app believes the meal is.
///
/// Until v21 this fell back to a food kind's `sentenceName` when the model gave
/// no label — "french toast" is what you recognise, "Refined grains" is what it
/// counted as. There is no taxonomy to fall back to now, and no need for one:
/// `label` is required.
enum FoodPhrase {
    static func word(for item: MealItem) -> String {
        item.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
