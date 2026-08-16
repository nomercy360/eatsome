import EatsomeCore
import SwiftUI

/// The note row, in its three states: an invitation, a card, an editor.
///
/// A note is `personalNote` — something you wrote for yourself afterwards,
/// input to nothing. It is not `note`, which is what you told the model the
/// photo could not show and is kept as half the input that produced the
/// dishes. The two look alike on a screen and are different things in the
/// log, so this view only ever touches the first.
struct MealNoteRow: View {
    let note: String?
    let onEdit: () -> Void

    var body: some View {
        if let note, !note.isEmpty {
            card(note)
        } else {
            invitation
        }
    }

    private var invitation: some View {
        Button(action: onEdit) {
            HStack(spacing: 14) {
                QuoteMark()
                Text("Add a note")
                    .font(WellieTheme.font(15, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .wellieSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func card(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                QuoteMark()
                Text(text)
                    .font(WellieTheme.font(15, weight: .regular))
                    .foregroundStyle(WellieTheme.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                // "Note · visible at your table" in the mock. Tables is cut,
                // and what is true instead is stated: nobody else sees it.
                Text("Note · only you see this")
                    .font(WellieTheme.font(12, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                Spacer()
                Button("Edit", action: onEdit)
                    .font(WellieTheme.font(12.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.accent)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(WellieTheme.hairline).frame(height: 1) }
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .wellieSurface(border: WellieTheme.accent, lineWidth: 1.5)
    }
}

/// The 30×30 raised circle with a closing quote mark in it.
struct QuoteMark: View {
    var body: some View {
        Circle()
            .fill(WellieTheme.accent.opacity(0.35))
            .frame(width: 30, height: 30)
            .overlay {
                Text("”")
                    .font(WellieTheme.font(18, weight: .bold))
                    .foregroundStyle(WellieTheme.onAccent)
                    .offset(y: 3)
            }
            .accessibilityHidden(true)
    }
}

/// Frame 7. Full screen, keyboard up, one thing to do.
///
/// There is no delete button: clearing the text removes the note, and the
/// footer says so. `Done` commits — an empty note commits as no note.
struct MealNoteEditor: View {
    let title: String
    @State var text: String
    let onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(WellieTheme.font(14, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                Spacer()
                Button("Done") {
                    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    onDone(trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                }
                .font(WellieTheme.font(14, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            }
            .padding(.horizontal, 26)
            .padding(.top, 14)

            Text("A note for yourself")
                .font(WellieTheme.font(25, weight: .heavy))
                .tracking(-0.6)
                .foregroundStyle(WellieTheme.ink)
                .padding(.horizontal, 24)
                .padding(.top, 26)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    QuoteMark()
                    TextField("A note for yourself", text: $text, axis: .vertical)
                        .font(WellieTheme.font(15, weight: .regular))
                        .foregroundStyle(WellieTheme.ink)
                        .lineSpacing(4)
                        .focused($focused)
                        .submitLabel(.return)
                }
                HStack {
                    Text("Clear the text to remove the note")
                        .font(WellieTheme.font(12, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                    Spacer()
                    Text("\(text.count)")
                        .font(WellieTheme.figure(12.5, weight: .regular))
                        .foregroundStyle(WellieTheme.muted)
                        .monospacedDigit()
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(WellieTheme.hairline).frame(height: 1) }
                .padding(.top, 14)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .wellieSurface(border: WellieTheme.accent, lineWidth: 1.5)
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 16)

            Spacer(minLength: 0)
        }
        .background(WellieTheme.background)
        .wellieScreen()
        .onAppear { focused = true }
    }
}
