import AuthenticationServices
import Foundation
import ShamanCore

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
///
/// It presents nothing itself. `SignInWithAppleButton` owns the controller and
/// the sheet, and this type owns the only thing the button cannot: the nonce,
/// whose hashed half goes to Apple on the request and whose raw half has to
/// survive until the result comes back. Splitting those across two objects is
/// how a binding stops binding anything.
@MainActor
final class AppleSignIn {
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

    private var nonce: SignInNonce.Pair?

    // MARK: - Driving Apple's own button

    /// Configure a request `SignInWithAppleButton` will perform itself.
    ///
    /// The button owns its controller, so the delegate path above never runs
    /// for it — but the nonce still has to be generated here, because the raw
    /// half must survive until `credential(from:)` reads it back. Building the
    /// request anywhere else would mean the value sent to Apple and the value
    /// sent to the server came from two different places, which is exactly the
    /// binding the nonce exists to make.
    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let pair = SignInNonce.generate()
        nonce = pair
        // Name and email are requested because Apple only ever offers them on
        // the very first authorization for an app — ask later and the answer is
        // permanently nil.
        request.requestedScopes = [.fullName, .email]
        request.nonce = pair.hashed
    }

    /// Read the button's result back into the same `Credential` the delegate
    /// path produces, so the caller has one shape to handle.
    func credential(from result: Result<ASAuthorization, any Error>) throws -> Credential {
        defer { nonce = nil }
        switch result {
        case .success(let authorization):
            let apple = authorization.credential as? ASAuthorizationAppleIDCredential
            guard
                let token = apple?.identityToken.flatMap({ String(data: $0, encoding: .utf8) }),
                let nonce
            else { throw Failure.noIdentityToken }
            return Credential(identityToken: token, nonce: nonce.raw)
        case .failure(let error):
            throw (error as? ASAuthorizationError)?.code == .canceled
                ? Failure.cancelled
                : Failure.underlying(error.localizedDescription)
        }
    }

}
