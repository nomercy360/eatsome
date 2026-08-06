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
struct FixScreen: View {
    /// What the person last told the model, so reopening this shows the words
    /// already taken into account rather than an empty box that implies they
    /// were forgotten.
    @Binding var text: String
    var onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTyping: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What should I fix?")
                        .font(WellieTheme.font(22, weight: .bold))
                    WellieProse("Say it like you'd tell a person. Your other edits are kept.", size: 15)
                }

                TextField("The toast is missing the eggs…", text: $text, axis: .vertical)
                    .font(WellieTheme.font(17, weight: .medium))
                    .focused($isTyping)
                    .lineLimit(2...6)
                    .padding(14)
                    .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isTyping ? WellieTheme.blue : .clear, lineWidth: 1.5)
                    }
                    .onSubmit(submit)

                Button("Update the meal", action: submit)
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
