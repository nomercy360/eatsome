import AuthenticationServices
import ShamanCore
import SwiftUI

/// The production entrance. A shared build token can start Apple's identity
/// exchange, but it cannot read or write any account data; the session returned
/// here is the only credential that opens the rest of the app.
struct SignInGateView: View {
    @Environment(AppModel.self) private var model

    @State private var signIn = AppleSignIn()
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Eat well\nwithout the\nbookkeeping.")
                    .font(WellieTheme.font(41, weight: .black))
                    .tracking(-1.5)
                    .foregroundStyle(WellieTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                WellieProse(
                    "Snap, type or say what you ate. We handle the numbers.",
                    size: 16
                )

                if let error {
                    Text(error)
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 108)

            Spacer(minLength: 60)

            SignInWithAppleButton(.continue) { request in
                signIn.prepare(request)
            } onCompletion: { result in
                Task { await finish(result) }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 52)
            .clipShape(RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous))
            .opacity(canSignIn ? 1 : 0.4)
            .disabled(!canSignIn)

            if !model.hasBackendAccess {
                WellieCaption("This build has no backend configuration, so Apple sign-in is unavailable.")
                    .padding(.top, 10)
            }

            Text("No feed, no followers. Your food stays yours.")
                .font(WellieTheme.font(11.5, weight: .regular))
                .foregroundStyle(WellieTheme.muted)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WellieTheme.background.ignoresSafeArea())
        .wellieScreen()
    }

    private var canSignIn: Bool { !busy && model.hasBackendAccess }

    private func finish(_ authorization: Result<ASAuthorization, any Error>) async {
        guard let backend = model.currentBackend else {
            error = "This build cannot reach the eatsome service."
            return
        }
        busy = true
        defer { busy = false }
        do {
            let credential = try signIn.credential(from: authorization)
            let result = try await backend.signIn(
                provider: .apple,
                identityToken: credential.identityToken,
                nonce: credential.nonce
            )
            await model.activateAccount(result)
            guard model.isSignedIn else {
                error = model.cloudError ?? "Your sign-in could not be saved on this phone."
                return
            }
            error = nil
        } catch AppleSignIn.Failure.cancelled {
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The signed-in account surface in Settings. Sign-in itself is the app gate,
/// so this card has one honest job: show the boundary and let this phone leave
/// it. Local history stays on disk, hidden until an account is authenticated.
struct AccountCard: View {
    @Environment(AppModel.self) private var model

    @State private var busy = false
    @State private var confirmingSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WellieSectionTitle(text: "Account", detail: "Signed in with Apple")

            HStack(spacing: 11) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(WellieTheme.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your meal log syncs to this account")
                        .font(WellieTheme.font(15, weight: .semibold))
                        .foregroundStyle(WellieTheme.ink)
                    WellieMeta("Sign in on another phone to see it there")
                }
                Spacer(minLength: 0)
            }

            WellieRowDivider()

            Button("Sign out on this phone") { confirmingSignOut = true }
                .font(WellieTheme.font(14.5, weight: .semibold))
                .foregroundStyle(WellieTheme.blue)
                .disabled(busy)
        }
        .wellieCard()
        .confirmationDialog(
            "Sign out on this phone?",
            isPresented: $confirmingSignOut,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) {
                busy = true
                Task {
                    await model.signOut()
                    busy = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local meals stay on this phone, but the app remains locked until you sign in with Apple again.")
        }
    }
}
