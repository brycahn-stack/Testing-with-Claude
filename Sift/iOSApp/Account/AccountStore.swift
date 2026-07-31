import Foundation
import Combine
import AuthenticationServices
import SiftCore

/// Owns the optional signed-in identity: Keychain persistence, Sign in with
/// Apple handling, and the Google identity flow.
///
/// Deliberately *not* a gatekeeper. Sift has no server, so there is nothing a
/// sign-in unlocks — every feature works signed out, and no code path should
/// ever check `account != nil` before doing work. The account exists to put a
/// name on the data and to be the seam a future sync/backup feature plugs into.
@MainActor
final class AccountStore: ObservableObject {
    @Published private(set) var account: UserAccount?
    @Published private(set) var busy = false
    @Published var lastError: String?

    private static let keychainKey = "user.account"
    private let googleIdentity = GoogleIdentity()

    init() {
        if let data = KeychainStore.load(account: Self.keychainKey) {
            account = try? JSONDecoder().decode(UserAccount.self, from: data)
        }
    }

    var isSignedIn: Bool { account != nil }

    // MARK: - Apple

    /// Completion handler for SwiftUI's `SignInWithAppleButton`.
    ///
    /// Apple shares the name and email **only on the first authorization** —
    /// every later sign-in returns nil for both. So if this user has signed in
    /// before, the stored name/email are carried forward rather than clobbered.
    func completeAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                lastError = "Unexpected credential type from Apple."
                return
            }

            let name = credential.fullName.flatMap { components -> String? in
                let formatted = PersonNameComponentsFormatter.localizedString(
                    from: components, style: .default
                )
                return formatted.isEmpty ? nil : formatted
            }

            let previous = account?.providerUserID == credential.user ? account : nil
            save(UserAccount(
                providerUserID: credential.user,
                provider: .apple,
                displayName: name ?? previous?.displayName,
                email: credential.email ?? previous?.email,
                createdAt: previous?.createdAt ?? Date()
            ))

        case .failure(let error):
            // Backing out of the sheet isn't an error worth surfacing.
            if let authError = error as? ASAuthorizationError, authError.code == .canceled { return }
            lastError = error.localizedDescription
        }
    }

    /// Apple lets users revoke an app's sign-in from Settings at any time.
    /// Checked on launch; a revoked credential signs out locally so the UI
    /// never shows an identity Apple no longer honors.
    func refreshAppleCredentialState() async {
        guard let account, account.provider == .apple else { return }
        let provider = ASAuthorizationAppleIDProvider()
        let state = try? await provider.credentialState(forUserID: account.providerUserID)
        if state == .revoked {
            signOut()
        }
    }

    // MARK: - Google

    /// Runs the Google identity flow (same PKCE machinery as the Connections
    /// tab, identity scopes instead of API scopes). Built and wired now, and
    /// simply disabled in the UI until the OAuth client ID lands — the moment
    /// `GoogleOAuthConfig.isConfigured` flips, this works.
    func signInWithGoogle() {
        guard GoogleOAuthConfig.isConfigured else {
            lastError = "Google sign-in needs the OAuth client ID from SETUP.md first."
            return
        }
        guard !busy else { return }
        busy = true
        lastError = nil

        Task {
            defer { busy = false }
            do {
                save(try await googleIdentity.signIn())
            } catch is CancellationError {
                // User dismissed the sheet.
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Same: user backed out.
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - Shared

    /// Signing out forgets the identity on this device. It deletes no data —
    /// the journal never belonged to the account in the first place.
    func signOut() {
        account = nil
        KeychainStore.delete(account: Self.keychainKey)
    }

    private func save(_ newAccount: UserAccount) {
        account = newAccount
        if let data = try? JSONEncoder().encode(newAccount) {
            KeychainStore.save(data, account: Self.keychainKey)
        }
    }
}
