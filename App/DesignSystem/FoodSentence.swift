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
        /// would score differently, and the question is asked below.
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
                    .background(WellieTheme.ice, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .opacity(word.isPending ? 0.55 : 1)
                    .overlay(alignment: .bottom) {
                        if word.isUncertain {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(WellieTheme.blue)
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
        switch words.count - index {
        case 1: "."
        case 2: ""
        default: ","
        }
    }
}

/// Builds the sentence's words from whatever the app currently believes the
/// meal is. The model's own label wins when it has one — "french toast" is
/// what you recognise; "Refined grains" is what it counts as.
enum FoodPhrase {
    static func word(for group: FoodGroup, label: String?) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed.lowercased() }
        return group.sentenceName
    }
}
