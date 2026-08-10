import SwiftUI

/// Screen `2d`. Saying what is wrong, on a screen of its own.
///
/// This was a sheet first, and the keyboard was the reason it stopped being
/// one. A sheet has a height, the keyboard arrives a beat after it opens, and
/// the two negotiate in front of someone who is still reading: the detent
/// settles, then the field and the button jump to make room. Every workaround —
/// measuring the content, sizing the detent, pinning the button — is an attempt
/// to guess where the keyboard will leave things, and lands somewhere slightly
/// wrong.
///
/// A full screen has no such argument to have. The content sits at the top, the
/// keyboard covers empty space below it, and nothing moves at all. Cancel is
/// where a sheet's grab handle was, and does the same job with less ceremony.
///
/// It is a sentence, not a form: "say it like you'd tell a person".
///
/// Naming a new ingredient is the same screen with different words. It used to
/// be the ingredient sheet, which is pickers only — a row appended as
/// `.other` opened on "Something else / Something else" and "Not weighed", with
/// nowhere to type what the thing actually was. There is no picker for the name
/// of a food, and inventing one would ask a person to find "olive oil" in a
/// list of 26 groups instead of saying it.
struct FixScreen: View {
    /// Which of the two jobs this screen is doing. Both are one act — words in,
    /// a delta out — so the difference is copy and nothing else.
    enum Purpose {
        case fix
        case add
    }

    var purpose: Purpose = .fix
    /// What the person last told the model, so reopening this shows the words
    /// already taken into account rather than an empty box that implies they
    /// were forgotten. An addition starts empty every time: it names one food
    /// and is spent as soon as that food is on the list.
    @Binding var text: String
    var onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(WellieTheme.font(22, weight: .bold))
                    WellieProse(subtitle, size: 15)
                }

                TextField(placeholder, text: $text, axis: .vertical)
                    .font(WellieTheme.font(17, weight: .medium))
                    .focused($isTyping)
                    .lineLimit(2...6)
                    .padding(14)
                    .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: WellieTheme.cardRadius, style: .continuous)
                            .stroke(isTyping ? WellieTheme.blue : .clear, lineWidth: 1.5)
                    }
                    .onSubmit(submit)

                Button(actionTitle, action: submit)
                    .buttonStyle(WelliePrimaryButtonStyle())
                    .disabled(trimmed.isEmpty)

                // Everything above stays where it opened; this is the space the
                // keyboard covers.
                Spacer(minLength: 0)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WellieTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { isTyping = true }
        .wellieScreen()
    }

    private var title: String {
        switch purpose {
        case .fix: "What should I fix?"
        case .add: "What should I add?"
        }
    }

    /// The addition says out loud what happens next, because it is the answer
    /// to the question the old sheet raised and could not answer: the weight is
    /// not being asked for, it is being worked out.
    private var subtitle: String {
        switch purpose {
        case .fix: "Say it like you'd tell a person. Your other edits are kept."
        case .add: "Name it like you'd tell a person. It gets a weight and joins the list."
        }
    }

    private var placeholder: String {
        switch purpose {
        case .fix: "The toast is missing the eggs…"
        case .add: "A drizzle of olive oil…"
        }
    }

    private var actionTitle: String {
        switch purpose {
        case .fix: "Update the meal"
        case .add: "Add it"
        }
    }

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        guard !trimmed.isEmpty else { return }
        isTyping = false
        dismiss()
        onSubmit()
    }
}
