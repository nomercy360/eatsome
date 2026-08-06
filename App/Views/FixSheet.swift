import SwiftUI

/// Screen `2d`. One field, over the keyboard, for saying what is wrong.
///
/// The correction used to be a card on the screen you were already reading,
/// which put a keyboard over the sentence you were trying to check. Here the
/// sentence stays where it is and the ask arrives on top of it, so the thing
/// being corrected is never the thing being covered.
///
/// It is a sentence, not a form: "say it like you'd tell a person". The chips
/// are examples of the register rather than options to choose — tapping one
/// writes it into the field, where it can be edited like anything typed.
struct FixSheet: View {
    /// What the person last told the model, so reopening the sheet shows the
    /// words already taken into account rather than an empty box that implies
    /// they were forgotten.
    @Binding var text: String
    var onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTyping: Bool

    private static let examples = ["no tomatoes", "fried in butter", "it's a bigger portion"]

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
                    .lineLimit(2...5)
                    .padding(14)
                    .background(WellieTheme.well, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onSubmit(submit)

                FlowLayout(spacing: 8, lineSpacing: 8) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button { text = example } label: {
                            WellieChip(text: example, style: .soft)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer(minLength: 0)

                Button("Update the meal", action: submit)
                    .buttonStyle(WelliePrimaryButtonStyle())
                    .disabled(trimmed.isEmpty)
            }
            .wellieColumn()
            .background(WellieTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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
