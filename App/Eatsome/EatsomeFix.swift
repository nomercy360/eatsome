import EatsomeCore
import SwiftUI

/// Saying what is wrong, in words, on a screen of its own.
///
/// A sheet first, and the keyboard is why it stopped being one. A sheet has a
/// height, the keyboard arrives a beat after it opens, and the two negotiate in
/// front of somebody who is still reading. A full screen has no such argument
/// to have: the content sits at the top, the keyboard covers empty space below
/// it, and nothing moves.
///
/// It is a sentence, not a form. There is no picker for the name of a food and
/// inventing one would ask a person to find "olive oil" in a list instead of
/// saying it — which is also why *adding* an ingredient arrives here rather
/// than at a row with an empty name and a weight field.
///
/// The words go to `BackendSession.refine`, which re-prices everything it
/// renames. That is the whole reason corrections in words exist beside the
/// chips: a chip can only offer a rival the model already priced, and this can
/// name something it never mentioned.
struct FixInWords: View {
    /// Both jobs are one act — words in, a delta out — so the difference is
    /// copy and nothing else.
    enum Purpose { case fix, add }

    var purpose: Purpose = .fix
    /// What the meal is, for the line above the field. Nothing is derived from
    /// it; it is there so the screen is about a particular plate.
    var subject: String
    /// What was last said, so reopening shows the words already taken into
    /// account rather than an empty box that implies they were forgotten. An
    /// addition starts empty every time: it names one food and is spent as soon
    /// as that food is on the list.
    var initialText: String = ""
    var isWorking = false
    var failure: String?
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String = ""
    @FocusState private var typing: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Cancel", action: onCancel)
                    .font(WellieTheme.font(14.5, weight: .semibold))
                    .foregroundStyle(WellieTheme.muted)
                Spacer()
                Text(subject)
                    .font(WellieTheme.font(14, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 16)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(WellieTheme.font(22, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                WellieProse(subtitle, size: 15)
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 22)

            TextField(placeholder, text: $text, axis: .vertical)
                .font(WellieTheme.font(17, weight: .medium))
                .foregroundStyle(WellieTheme.ink)
                .focused($typing)
                .lineLimit(2...6)
                .padding(14)
                .wellieSurface(WellieTheme.well, border: typing ? WellieTheme.accent : WellieTheme.hairline, lineWidth: 1.5)
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 18)
                .disabled(isWorking)

            if let failure {
                Text(failure)
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, WellieTheme.screenInset)
                    .padding(.top, 12)
            }

            Button(action: submit) {
                if isWorking {
                    ProgressView().tint(WellieTheme.onAccent)
                } else {
                    Text(actionTitle)
                }
            }
            .buttonStyle(WelliePrimaryButtonStyle(enabled: !trimmed.isEmpty && !isWorking))
            .disabled(trimmed.isEmpty || isWorking)
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.top, 16)

            // Everything above stays where it opened; this is the space the
            // keyboard covers.
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WellieTheme.background)
        .wellieScreen()
        .onAppear {
            text = initialText
            typing = true
        }
    }

    private func submit() {
        guard !trimmed.isEmpty, !isWorking else { return }
        typing = false
        onSubmit(trimmed)
    }

    private var title: String {
        switch purpose {
        case .fix: "What should I fix?"
        case .add: "What should I add?"
        }
    }

    /// The addition says out loud what happens next, because it answers the
    /// question a weight field would raise: the weight is not being asked for,
    /// it is being worked out.
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
}

/// Running a correction in words against the Worker.
///
/// A free function rather than a method on either lane, because both lanes do
/// exactly this and neither owns it: the composer corrects a meal that is not
/// in the log yet, and the detail corrects one that is. The difference is what
/// the caller does with the result, which is the caller's business.
enum MealRefinement {
    /// What came of it. Not `Result`: the failure side is a sentence for a
    /// person to read rather than an error anything catches, and wrapping it in
    /// an `Error` conformance would be ceremony around a string.
    enum Outcome {
        case success(MealEntry)
        case failure(String)
    }

    /// The meal with the correction applied, or the failure in words.
    ///
    /// The photograph goes up as its hash when the meal has one, so the model
    /// looks at the plate it read rather than only at the sentence. Without one
    /// the same prompt runs on the list and the words alone, and the contract
    /// is identical either way.
    static func apply(
        _ note: String,
        to meal: MealEntry,
        using session: BackendSession?
    ) async -> Outcome {
        guard let session else {
            return .failure("This build cannot reach the eatsome service.")
        }
        do {
            let revision = try await session.refine(
                meal: meal.dishes,
                note: note,
                photoHash: PhotoStore.shared.contains(meal.photoHash) ? meal.photoHash : nil
            )
            guard !revision.isEmpty else {
                return .failure("Nothing in that changed the meal. Try naming the food.")
            }
            return .success(revision.applied(to: meal))
        } catch {
            return .failure(error.localizedDescription)
        }
    }
}
