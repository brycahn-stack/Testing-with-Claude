import Foundation
import UIKit
import AuthenticationServices
import CryptoKit

/// Drives the Connections screen: tracks which Google services are connected and
/// runs the OAuth sign-in flow (ASWebAuthenticationSession + PKCE — the standard
/// secretless flow for mobile apps).
@MainActor
final class GoogleConnectionsModel: NSObject, ObservableObject {
    @Published private(set) var connected: Set<GoogleService> = []
    @Published private(set) var busy: GoogleService?
    @Published var lastError: String?

    override init() {
        super.init()
        Task { await refreshStates() }
    }

    func refreshStates() async {
        var result: Set<GoogleService> = []
        for service in GoogleService.allCases where await GoogleAuthStore.shared.isConnected(service) {
            result.insert(service)
        }
        connected = result
    }

    func isConnected(_ service: GoogleService) -> Bool { connected.contains(service) }

    func disconnect(_ service: GoogleService) {
        Task {
            await GoogleAuthStore.shared.disconnect(service)
            await refreshStates()
        }
    }

    func connect(_ service: GoogleService) {
        guard GoogleOAuthConfig.isConfigured else {
            lastError = "Add your Google OAuth client ID in GoogleService.swift first."
            return
        }
        guard busy == nil else { return }
        busy = service
        lastError = nil

        Task {
            defer { busy = nil }
            do {
                let token = try await runOAuthFlow(for: service)
                await GoogleAuthStore.shared.store(token, for: service)
                await refreshStates()
            } catch is CancellationError {
                // User dismissed the sheet — not an error worth surfacing.
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                // Same: user backed out.
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    // MARK: - OAuth flow

    private func runOAuthFlow(for service: GoogleService) async throws -> GoogleToken {
        // PKCE: random verifier, SHA256 challenge.
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
            URLQueryItem(name: "scope", value: service.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            // Ask for a refresh token so the connection survives token expiry.
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]

        let callbackURL = try await presentAuthSession(
            url: components.url!,
            callbackScheme: GoogleOAuthConfig.redirectScheme
        )

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.refreshFailed("No authorization code in callback")
        }

        return try await exchangeCode(code, verifier: verifier)
    }

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

    private func exchangeCode(_ code: String, verifier: String) async throws -> GoogleToken {
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

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleToken(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token,
            expiresAt: Date().addingTimeInterval(decoded.expires_in)
        )
    }

    private static func randomURLSafeString(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).compactMap { _ in chars.randomElement() })
    }
}

extension GoogleConnectionsModel: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
