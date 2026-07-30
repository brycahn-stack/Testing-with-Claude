import Foundation

/// A stored Google OAuth grant for one service.
struct GoogleToken: Codable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { Date() >= expiresAt.addingTimeInterval(-60) }
}

enum GoogleAuthError: Error, LocalizedError {
    case notConfigured
    case notConnected
    case refreshFailed(String)
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:          return "Google client ID not set up yet (see GoogleService.swift)."
        case .notConnected:           return "This Google service isn't connected."
        case .refreshFailed(let m):   return "Couldn't refresh Google sign-in: \(m)"
        case .httpError(let c, let m): return "Google API error \(c): \(m)"
        }
    }
}

/// Owns Google tokens: Keychain persistence, expiry checks, and refresh.
/// An actor so destinations can safely ask for tokens from any context.
actor GoogleAuthStore {
    static let shared = GoogleAuthStore()

    private var cache: [GoogleService: GoogleToken] = [:]

    func isConnected(_ service: GoogleService) -> Bool {
        token(for: service) != nil
    }

    func store(_ token: GoogleToken, for service: GoogleService) {
        cache[service] = token
        if let data = try? JSONEncoder().encode(token) {
            KeychainStore.save(data, account: service.rawValue)
        }
    }

    func disconnect(_ service: GoogleService) {
        cache[service] = nil
        KeychainStore.delete(account: service.rawValue)
    }

    /// Returns a fresh access token, refreshing via the refresh token if needed.
    func validAccessToken(for service: GoogleService) async throws -> String {
        guard GoogleOAuthConfig.isConfigured else { throw GoogleAuthError.notConfigured }
        guard var token = token(for: service) else { throw GoogleAuthError.notConnected }

        if !token.isExpired { return token.accessToken }

        guard let refreshToken = token.refreshToken else { throw GoogleAuthError.notConnected }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoder.encode([
            "client_id": GoogleOAuthConfig.clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            // A revoked grant means we're effectively disconnected.
            disconnect(service)
            throw GoogleAuthError.refreshFailed(body)
        }

        struct RefreshResponse: Decodable {
            let access_token: String
            let expires_in: Double
        }
        let decoded = try JSONDecoder().decode(RefreshResponse.self, from: data)
        token.accessToken = decoded.access_token
        token.expiresAt = Date().addingTimeInterval(decoded.expires_in)
        store(token, for: service)
        return token.accessToken
    }

    private func token(for service: GoogleService) -> GoogleToken? {
        if let cached = cache[service] { return cached }
        guard let data = KeychainStore.load(account: service.rawValue),
              let token = try? JSONDecoder().decode(GoogleToken.self, from: data) else { return nil }
        cache[service] = token
        return token
    }
}

/// application/x-www-form-urlencoded body encoding.
enum FormEncoder {
    static func encode(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params
            .map { key, value in
                let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(k)=\(v)"
            }
            .joined(separator: "&")
            .data(using: .utf8) ?? Data()
    }
}
