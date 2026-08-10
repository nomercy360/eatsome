import ShamanCore
import SwiftUI

/// The only surface accounts have, and it is behind five taps on the version
/// row (`2i` → Workshop).
///
/// M4 is a server milestone: sign-in exists so that a table can have members,
/// and until tables ship there is nothing for a person to do with an account.
/// A visible "Sign in" button in Settings before then would be asking for an
/// identity in exchange for nothing, so this card lives in the workshop, where
/// the provider switch and the counters already are — it is a way to exercise
/// the flow, not a feature.
///
/// Drop it into `WorkshopView`'s stack with `SignInWorkshopSection()`. It is a
/// separate file rather than another card inside `SettingsView.swift` only
/// because that file was being rewritten alongside this work.
struct SignInWorkshopSection: View {
    @Environment(AppModel.self) private var model

    @State private var signIn = AppleSignIn()
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(
                text: "Account",
                detail: "Signing in hands this device's history to the account, permanently. Nothing here is user-facing until tables ship."
            )

            if let accountID = model.signedInAccountID {
                labelled("Account", accountID)
            } else {
                Text("Not signed in. This device's meals belong to the device.")
                    .font(WellieTheme.font(13.5, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }

            if let status {
                Text(status)
                    .font(WellieTheme.font(13, weight: .medium))
                    .foregroundStyle(WellieTheme.muted)
            }

            if model.signedInAccountID == nil {
                Button("Sign in with Apple") { Task { await authorize() } }
                    .buttonStyle(WelliePrimaryButtonStyle(enabled: !busy && model.hasBackendAccess))
                    .disabled(busy || !model.hasBackendAccess)
            } else {
                // Signing out is not un-merging, and the copy says so rather
                // than letting someone believe it undoes the adoption above.
                Button("Sign out (history stays with the account)", role: .destructive) {
                    Task { await signOut() }
                }
                .font(WellieTheme.font(13.5, weight: .semibold))
                .disabled(busy)
            }
        }
        .wellieCard()
    }

    private func authorize() async {
        guard let backend = model.currentBackend else { return }
        busy = true
        defer { busy = false }
        do {
            let credential = try await signIn.authorize()
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
                "This device was already claimed by another account. Its earlier meals stayed there; new ones go to this account."
            } else if result.merge.adopted {
                "This device's earlier meals now belong to this account. That cannot be undone."
            } else {
                "Signed in."
            }
        } catch AppleSignIn.Failure.cancelled {
            status = nil
        } catch {
            status = error.localizedDescription
        }
    }

    private func signOut() async {
        busy = true
        defer { busy = false }
        // Server first: clearing the token locally on a failed call would leave
        // a session alive that nothing can now revoke.
        do { try await model.currentBackend?.signOut() } catch {
            status = error.localizedDescription
            return
        }
        model.setSessionToken(nil)
        model.rememberAccountID(nil)
        status = "Signed out on this device."
    }

    private func labelled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(WellieTheme.font(15, weight: .semibold))
            Spacer()
            Text(value)
                .font(WellieTheme.font(12, weight: .medium))
                .foregroundStyle(WellieTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
