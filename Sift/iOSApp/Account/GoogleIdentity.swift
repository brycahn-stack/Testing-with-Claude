import Foundation
import UIKit
import AuthenticationServices
import CryptoKit
import SiftCore

/// The Google *identity* flow — "who is this user", nothing more.
///
/// Same OAuth client and same PKCE dance as the Gmail/Calendar connections, but
/// with the identity scopes (`openid email profile`) instead of API scopes, and
/// one deliberate difference at the end: **no tokens are kept.** Identity needs
/// exactly one round trip — the `id_token` in the code-exchange response carries
/// the name and email, Sift reads them, and the tokens are dropped. There is no
/// ongoing Google access to store, refresh, or revoke.
///
/// Uses the client ID Ben is creating for the connections — identity scopes are
/// non-sensitive, so they add no verification burden to the Google Cloud setup.
final class GoogleIdentity: NSObject {

    /// Runs the flow and returns the account. Throws `.notConfigured` until the
    /// OAuth client ID is pasted into `GoogleService.swift`.
    func signIn() async throws -> UserAccount {
        guard GoogleOAuthConfig.isConfigured else { throw GoogleAuthError.notConfigured }

        // PKCE: random verifier, SHA256 challenge — same shape as the
        // connections flow.
        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // No access_type=offline: identity is one round trip, so a refresh
            // token would be stored access Sift never uses.
            URLQueryItem(name: "prompt", value: "select_account")
        ]

        let callbackURL = try await presentAuthSession(
            url: components.url!,
            callbackScheme: GoogleOAuthConfig.redirectScheme
        )

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.refreshFailed("No authorization code in callback")
        }

        return try await exchangeForIdentity(code: code, verifier: verifier)
    }

    // MARK: - Token exchange → identity

    private func exchangeForIdentity(code: String, verifier: String) async throws -> UserAccount {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoder.encode([
            "client_id": GoogleOAuthConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuthConfig.redirectURI
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GoogleAuthError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                String(data: data, encoding: .utf8) ?? ""
            )
        }

        struct TokenResponse: Decodable { let id_token: String? }
        guard let idToken = try JSONDecoder().decode(TokenResponse.self, from: data).id_token else {
            throw GoogleAuthError.refreshFailed("No id_token in Google's response")
        }

        return try Self.account(fromIDToken: idToken)
    }

    /// Reads the identity claims out of the JWT's payload segment.
    ///
    /// The signature is *not* verified, on purpose: verification exists to let a
    /// third party trust a token it was handed. This token arrived directly
    /// from Google's token endpoint over TLS in the same breath as the code
    /// exchange, and it's used only to label a local profile — there's no
    /// server session to protect.
    static func account(fromIDToken idToken: String) throws -> UserAccount {
        let segments = idToken.split(separator: ".")
        guard segments.count == 3,
              let payload = base64URLDecode(String(segments[1])) else {
            throw GoogleAuthError.refreshFailed("Malformed id_token")
        }

        struct Claims: Decodable {
            let sub: String
            let email: String?
            let name: String?
        }
        let claims = try JSONDecoder().decode(Claims.self, from: payload)

        return UserAccount(
            providerUserID: claims.sub,
            provider: .google,
            displayName: claims.name,
            email: claims.email
        )
    }

    /// Base64url (no padding) → Data, as JWTs are encoded.
    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }

    // MARK: - Web auth session

    private func presentAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private static func randomURLSafeString(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
}

extension GoogleIdentity: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
