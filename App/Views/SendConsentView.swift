import ShamanCore
import SwiftUI

/// Explicit permission before the first message leaves the phone.
///
/// Kept separate from camera authorization: access to a sensor is not consent to
/// cloud storage or to disclosure to a third-party AI provider.
///
/// It covers words as well as photographs now, because the thread does. When
/// logging was photo-first this screen could honestly say "before this photo is
/// read"; a typed meal goes to exactly the same provider, and a consent screen
/// that named only the picture would be describing half of what happens. The
/// wording leads with whichever is actually about to be sent, and states both.
struct SendConsentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    /// True when the message being sent has a photograph. Changes the emphasis,
    /// never the substance — everything on this screen is true either way.
    var includesPhoto: Bool
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(includesPhoto ? "Before this photo is read" : "Before this is read")
                        .font(WellieTheme.font(26, weight: .bold))
                    WellieProse(summary, size: 16)

                    VStack(alignment: .leading, spacing: 12) {
                        if includesPhoto {
                            point(
                                "Stored for retries",
                                """
                                The private cloud copy lets you retry recognition without \
                                uploading again.
                                """
                            )
                        }
                        point(
                            "Kept to this phone",
                            """
                            Anything stored is filed under this install's own id, so no other \
                            tester's app can reach it.
                            """
                        )
                        point(
                            "Delete whenever you want",
                            """
                            Deleting a meal removes its cloud copy when no other meal uses it; \
                            Settings can erase all cloud data and withdraw consent.
                            """
                        )
                        point(
                            "Research use is separate",
                            "Nothing joins eatsome's research corpus unless you separately opt in."
                        )
                    }
                    .wellieCard(color: WellieTheme.ice)
                }
                .wellieColumn()
            }
            .background(WellieTheme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    Button(includesPhoto ? "Agree and send this photo" : "Agree and send this") {
                        onAgree()
                        dismiss()
                    }
                    .buttonStyle(WelliePrimaryButtonStyle())
                    Button("Not now") {
                        onCancel()
                        dismiss()
                    }
                    .buttonStyle(WellieQuietButtonStyle())
                }
                .padding(.horizontal, WellieTheme.screenInset)
                .padding(.vertical, 12)
                .background(WellieTheme.background)
            }
        }
        .interactiveDismissDisabled()
        .wellieScreen()
    }

    private var summary: String {
        let provider = model.provider.displayName
        if includesPhoto {
            return """
            eatsome will store the 2048-pixel meal image in its private Cloudflare R2 bucket \
            and send it, with anything you typed, to \(provider) to identify foods.
            """
        }
        return """
        eatsome will send what you write or say about a meal to \(provider) to identify foods. \
        Photos you send later are stored in its private Cloudflare R2 bucket as well.
        """
    }

    private func point(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(WellieTheme.font(15.5, weight: .bold))
            Text(detail)
                .font(WellieTheme.font(13.5, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
        }
    }
}
