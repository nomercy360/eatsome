import AuthenticationServices
import EatsomeCore
import SwiftUI

/// The entrance. Apple proves who you are once; the session the Worker mints in
/// exchange is the credential on every request after that.
///
/// It is the first screen when no valid session is stored, rather than a row in
/// You, because the account is the boundary the history is filed under — a
/// phone logging meals into nowhere and being offered sign-in later is how you
/// end up owning two histories and merging them badly.
struct SignInGate: View {
    @Environment(EatsomeAccount.self) private var account

    /// The one legitimate scheme read in the app.
    ///
    /// `signInWithAppleButtonStyle` takes an enum Apple owns, not a colour, so
    /// no `WellieTheme` pair can carry it — and the wrong end of that enum is
    /// not merely off-palette, it is a white button on a near-white page with a
    /// 1 pt system edge to say it is there. Every other colour in the app is
    /// resolved by UIKit at draw time instead of captured here.
    @Environment(\.colorScheme) private var colorScheme

    @State private var signIn = AppleSignIn()
    @State private var failure: String?
    @State private var busy = false

    var body: some View {
        ZStack(alignment: .top) {
            // The one atmospheric gesture in the entrance: the action lime is
            // already present before there is an action to tap, as light rather
            // than as a second control.
            RadialGradient(
                colors: [WellieTheme.accent.opacity(0.42), WellieTheme.accent.opacity(0)],
                center: .center,
                startRadius: 0,
                endRadius: 112
            )
            .frame(width: 320, height: 220)
            .offset(y: 86)
            .blur(radius: 4)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Eat well\nwithout the\nbookkeeping.")
                        .font(WellieTheme.font(41, weight: .black))
                        .tracking(-1.5)
                        .foregroundStyle(WellieTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    WellieProse("Photograph it or say what it was. We work out the numbers.", size: 16)

                    if let failure {
                        Text(failure)
                            .font(WellieTheme.font(13, weight: .medium))
                            .foregroundStyle(WellieTheme.danger)
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
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: WellieTheme.controlRadius, style: .continuous))
                .disabled(busy)

                Text("No feed, no followers. Your food stays yours.")
                    .font(WellieTheme.font(11.5, weight: .regular))
                    .foregroundStyle(WellieTheme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, WellieTheme.screenInset)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .wellieScreen()
    }

    private func finish(_ authorization: Result<ASAuthorization, any Error>) async {
        busy = true
        defer { busy = false }
        do {
            await account.signIn(try signIn.credential(from: authorization))
            // A cancelled sign-in is not a failure and says nothing; anything
            // else the account could not complete is reported in its own words.
            failure = account.isSignedIn ? nil : account.error
        } catch AppleSignIn.Failure.cancelled {
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}
