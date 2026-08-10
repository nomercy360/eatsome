import AuthenticationServices
import Foundation
import ShamanCore
import UIKit

/// Sign in with Apple, and nothing else.
///
/// Lives in `App/` because `AuthenticationServices` is a framework and `Core/`
/// does not import frameworks. Everything this hands back is a string: the
/// identity token Apple signed and the raw nonce that binds it to this attempt.
/// The phone never decides who anybody is — it carries a signed claim to the
/// server, which verifies it (`Backend/worker/lib/identity-token.ts`) and is the
/// only place a `sub` is believed.
///
/// Apple's identity token is deliberately not stored. It lives about ten
/// minutes and cannot be refreshed without another Face ID prompt, so it is a
/// sign-in credential, not a session credential; what gets kept in the Keychain
/// is the opaque session token the server mints in exchange for it.
@MainActor
final class AppleSignIn: NSObject {
    struct Credential: Sendable {
        let identityToken: String
        /// Raw, not hashed. The hash went to Apple; the server hashes this and
        /// compares, so sending the hash here would satisfy the check while
        /// proving nothing.
        let nonce: String
    }

    enum Failure: Error, LocalizedError {
        case cancelled
        case noIdentityToken
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Sign in was cancelled."
            case .noIdentityToken: "Apple returned an authorization with no identity token."
            case .underlying(let message): message
            }
        }
    }

    private var continuation: CheckedContinuation<Credential, Error>?
    private var nonce: SignInNonce.Pair?

    func authorize() async throws -> Credential {
        // One at a time. A second prompt while the first is open would take
        // over the continuation and strand the first caller forever.
        if continuation != nil { throw Failure.underlying("A sign-in is already in progress.") }

        let pair = SignInNonce.generate()
        nonce = pair

        let request = ASAuthorizationAppleIDProvider().createRequest()
        // Name and email are requested because Apple only ever offers them on
        // the very first authorization for an app — ask later and the answer is
        // permanently nil. Nothing here stores either: the server keeps the
        // `sub` and, for support, the email off the token. They are asked for
        // so that the option is not thrown away.
        request.requestedScopes = [.fullName, .email]
        request.nonce = pair.hashed

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    private func finish(_ result: Result<Credential, Error>) {
        let pending = continuation
        continuation = nil
        nonce = nil
        pending?.resume(with: result)
    }
}

extension AppleSignIn: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let token = credential?.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in
            guard let token, let nonce = self.nonce else {
                return self.finish(.failure(Failure.noIdentityToken))
            }
            self.finish(.success(Credential(identityToken: token, nonce: nonce.raw)))
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        Task { @MainActor in
            self.finish(.failure(cancelled ? Failure.cancelled : Failure.underlying(error.localizedDescription)))
        }
    }
}

extension AppleSignIn: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
        }
    }
}
