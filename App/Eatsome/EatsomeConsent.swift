import SwiftUI

/// Explicit permission before the first thing leaves the phone.
///
/// Kept separate from camera and photo authorization on purpose: access to a
/// sensor or a library is not consent to cloud storage, and neither is consent
/// to disclosure to a third-party model provider. iOS asks the first question;
/// this asks the second.
///
/// It covers words as well as photographs, because both go to the same place. A
/// consent screen that named only the picture would be describing half of what
/// happens, so the emphasis follows whichever is about to be sent and both are
/// stated either way.
struct SendConsentSheet: View {
    /// True when what is about to be sent has a photograph. Changes the
    /// emphasis, never the substance — everything here is true both ways.
    var includesPhoto: Bool
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(includesPhoto ? "Before this photo is read" : "Before this is read")
                        .font(WellieTheme.font(24, weight: .bold))
                        .foregroundStyle(WellieTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    WellieProse(summary, size: 15.5)

                    VStack(alignment: .leading, spacing: 14) {
                        if includesPhoto {
                            point(
                                "Stored for retries",
                                "The private cloud copy is what lets a correction look at the plate again, and a new phone get the picture back."
                            )
                        }
                        point(
                            "Kept to your account",
                            "Anything stored is filed under the account you signed in with. Nothing else can reach it."
                        )
                        point(
                            "Delete whenever you want",
                            "Deleting a meal removes its cloud copy. You can erase everything the account holds, and withdraw this, from You."
                        )
                    }
                    .wellieCard()
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.top, 28)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 8) {
                Button(includesPhoto ? "Agree and send this photo" : "Agree and send this", action: onAgree)
                    .buttonStyle(WelliePrimaryButtonStyle())
                Button("Not now", action: onCancel)
                    .buttonStyle(WellieQuietButtonStyle())
            }
            .padding(.horizontal, WellieTheme.screenInset)
            .padding(.bottom, 16)
        }
        .background(WellieTheme.background)
        .interactiveDismissDisabled()
        .wellieScreen()
    }

    /// Gemini is named rather than called "our AI partner". A person agreeing
    /// to disclosure is entitled to know who to.
    private var summary: String {
        includesPhoto
            ? """
              eatsome stores the meal image privately under your account and sends it, with \
              anything you typed, to Google Gemini to identify the food and weigh it.
              """
            : """
              eatsome sends what you write about a meal to Google Gemini to identify the food \
              and weigh it. A photo you send later is stored privately under your account too.
              """
    }

    private func point(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(WellieTheme.font(15, weight: .bold))
                .foregroundStyle(WellieTheme.ink)
            Text(detail)
                .font(WellieTheme.font(13.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
