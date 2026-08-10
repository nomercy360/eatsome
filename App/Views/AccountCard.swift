import AuthenticationServices
import ShamanCore
import SwiftUI

/// The production entrance. A shared build token can start Apple's identity
/// exchange, but it cannot read or write any account data; the session returned
/// here is the only credential that opens the rest of the app.
struct SignInGateView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    @State private var signIn = AppleSignIn()
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("eatsome")
                .font(WellieTheme.font(15, weight: .bold))
                .padding(.top, 12)

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 22) {
                OliveRow(olives: 5, size: 22)

                Text("Your meals are yours.\nSign in to keep them that way.")
                    .font(WellieTheme.font(30, weight: .bold))
                    .foregroundStyle(WellieTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                WellieProse(
                    "Sign in with Apple to use eatsome. Your meal log syncs privately to your account, including history already on this phone.",
                    size: 16
                )

                VStack(alignment: .leading, spacing: 11) {
                    point("No shared or anonymous account")
                    point("Your history follows you to another phone")
                    point("No password, and no email unless you share it")
                }

                if let error {
                    Text(error)
                        .font(WellieTheme.font(13, weight: .medium))
                        .foregroundStyle(WellieTheme.attention)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 28)

            SignInWithAppleButton(.signIn) { request in
                signIn.prepare(request)
            } onCompletion: { result in
                Task { await finish(result) }
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            .opacity(canSignIn ? 1 : 0.4)
            .disabled(!canSignIn)

            if !model.hasBackendAccess {
                WellieCaption("This build has no backend configuration, so Apple sign-in is unavailable.")
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 26)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(WellieTheme.ice.ignoresSafeArea())
        .wellieScreen()
    }

    private var canSignIn: Bool { !busy && model.hasBackendAccess }

    private func point(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(WellieTheme.blue)
            Text(text)
                .font(WellieTheme.font(15, weight: .semibold))
                .foregroundStyle(WellieTheme.ink)
        }
    }

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
