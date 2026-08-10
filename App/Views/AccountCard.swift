import AuthenticationServices
import ShamanCore
import SwiftUI

/// Screen `2i`. Your account, in Settings where a person can find it.
///
/// This lived behind five taps on the version row while sign-in had nothing to
/// do: an account that unlocks nothing is an identity asked for in exchange for
/// nothing. Tables changed that — a table has members, and a member is a person
/// rather than a phone — so it comes out of the workshop and becomes an
/// ordinary card.
///
/// What it does not do is gate anything. The app has always worked signed out
/// and still does: the device is the account until somebody says otherwise, and
/// nothing here is a wall in front of logging a meal.
///
/// The button is Apple's own `SignInWithAppleButton` rather than a styled one
/// of ours. That is not deference to the design system's other buttons losing
/// an argument — Apple's guidelines require their button for their flow, and a
/// hand-rolled one is a review rejection as well as a control people have
/// learned to recognise by shape.
struct AccountCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    @State private var signIn = AppleSignIn()
    @State private var status: Status?
    @State private var busy = false
    @State private var confirmingSignOut = false

    /// What just happened, and how loudly to say it.
    ///
    /// A merge that adopted this device's history is irreversible and gets said
    /// plainly; a conflict left the old meals somewhere else and has to be said
    /// even louder, because the alternative is somebody quietly concluding
    /// their history was lost.
    private enum Status {
        case adopted
        case conflict
        case signedIn
        case signedOut
        case failed(String)

        var text: String {
            switch self {
            case .adopted:
                "Your meals on this phone now belong to your account. That can't be undone."
            case .conflict:
                "This phone was already signed in to a different account. Its earlier meals stayed there — new ones go to this account."
            case .signedIn: "Signed in."
            case .signedOut: "Signed out on this phone. Your meals stay with the account."
            case .failed(let message): message
            }
        }

        var isProblem: Bool {
            switch self {
            case .conflict, .failed: true
            default: false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(text: "Account", detail: detail)

            if model.signedInAccountID == nil { signedOut } else { signedIn }

            if let status {
                Text(status.text)
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(status.isProblem ? WellieTheme.attention : WellieTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .wellieCard()
        .confirmationDialog(
            "Sign out on this phone?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { Task { await signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your meals stay with your account and come back when you sign in again. Signing out does not undo joining this phone to the account.")
        }
    }

    private var detail: String {
        model.signedInAccountID == nil
            ? "Optional. eatsome works signed out — the phone is the account until you say otherwise."
            : "Signed in with Apple"
    }

    // MARK: - Signed out

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieProse(
                """
                Sign in so your week follows you to another phone, and so friends at a table know \
                which meals are yours. No password, and no email unless you choose to share one.
                """,
                size: 14
            )

            // Apple's button, driven by Apple's button. The nonce is still
            // minted in `AppleSignIn` — `prepare` sets the hashed half on the
            // request and keeps the raw half for `credential(from:)` — so the
            // value Apple signs and the value the server checks come from one
            // place, which is the whole point of the binding.
            //
            // Nothing about it is themed. It is the one control in this app
            // allowed to look like somebody else's: Apple's guidelines require
            // their button for their flow, and people recognise it by shape.
            SignInWithAppleButton(.signIn) { request in
                signIn.prepare(request)
            } onCompletion: { result in
                Task { await finish(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 48)
            .opacity(canSignIn ? 1 : 0.4)
            .disabled(!canSignIn)

            if !model.hasBackendAccess {
                WellieCaption("This build has no backend token, so signing in has nothing to talk to.")
            }
        }
    }

    private var canSignIn: Bool { !busy && model.hasBackendAccess }

    // MARK: - Signed in

    private var signedIn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(WellieTheme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your meals sync to this account")
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                    WellieMeta("Sign in on another phone to see them there")
                }
                Spacer(minLength: 0)
            }

            WellieRowDivider()

            Button("Sign out on this phone") { confirmingSignOut = true }
                .font(WellieTheme.font(14.5, weight: .semibold))
                .foregroundStyle(WellieTheme.blue)
                .disabled(busy)
        }
    }

    // MARK: - Doing it

    private func finish(_ authorization: Result<ASAuthorization, any Error>) async {
        guard let backend = model.currentBackend else { return }
        busy = true
        defer { busy = false }
        do {
            let credential = try signIn.credential(from: authorization)
            let result = try await backend.signIn(
                provider: .apple,
                identityToken: credential.identityToken,
                nonce: credential.nonce
            )
            model.setSessionToken(result.sessionToken)
            model.rememberAccountID(result.accountId)
            // The three outcomes read differently on purpose. "Adopted" is the
            // irreversible one; a conflict left the old history alone, and a
            // person who is told nothing would assume it had moved.
            status = if result.merge.conflict != nil {
                .conflict
            } else if result.merge.adopted {
                .adopted
            } else {
                .signedIn
            }
            await model.refreshTables()
        } catch AppleSignIn.Failure.cancelled {
            // Cancelling is a decision, not an error. Nothing on screen.
            status = nil
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func signOut() async {
        busy = true
        defer { busy = false }
        // Server first: clearing the token locally on a failed call would leave
        // a session alive that nothing can now revoke.
        do {
            try await model.currentBackend?.signOut()
        } catch {
            status = .failed(error.localizedDescription)
            return
        }
        model.setSessionToken(nil)
        model.rememberAccountID(nil)
        status = .signedOut
    }
}
