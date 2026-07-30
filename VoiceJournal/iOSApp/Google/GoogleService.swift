import Foundation
import SwiftUI

/// One-time Google setup. The app can't talk to Google APIs until you create an
/// iOS OAuth client and paste its ID here:
///
/// 1. console.cloud.google.com → create a project (e.g. "Voice Journal").
/// 2. APIs & Services → Library → enable **Gmail API** and **Google Calendar API**.
/// 3. APIs & Services → OAuth consent screen → External → add yourself as a test user.
/// 4. Credentials → Create Credentials → OAuth client ID → **iOS** →
///    bundle ID `com.example.VoiceJournal` → copy the client ID.
///
/// iOS OAuth clients have no secret; the flow below uses PKCE, which is Google's
/// required/recommended approach for mobile.
enum GoogleOAuthConfig {
    /// Paste your iOS OAuth client ID, e.g. "1234567890-abc123.apps.googleusercontent.com"
    static let clientID = "YOUR_CLIENT_ID.apps.googleusercontent.com"

    /// Google iOS clients redirect to the reversed client ID as a URL scheme.
    static var redirectScheme: String {
        clientID.split(separator: ".").reversed().joined(separator: ".")
    }

    static var redirectURI: String { "\(redirectScheme):/oauth2redirect" }

    /// True once a real client ID has been pasted in.
    static var isConfigured: Bool { !clientID.hasPrefix("YOUR_CLIENT_ID") }
}

/// The Google services the app can connect to — each is authorized separately so
/// the user grants exactly what they're comfortable with.
enum GoogleService: String, CaseIterable, Identifiable, Codable, Sendable {
    case gmail
    case googleCalendar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gmail:          return "Gmail"
        case .googleCalendar: return "Google Calendar"
        }
    }

    var blurb: String {
        switch self {
        case .gmail:
            return "Turn \"email Sarah about the deck\" into a ready-to-send Gmail draft."
        case .googleCalendar:
            return "Send scheduling memos to Google Calendar instead of the local calendar."
        }
    }

    /// Minimal scopes: drafts only for Gmail (no read access), events only for
    /// Calendar (no full calendar access).
    var scopes: [String] {
        switch self {
        case .gmail:          return ["https://www.googleapis.com/auth/gmail.compose"]
        case .googleCalendar: return ["https://www.googleapis.com/auth/calendar.events"]
        }
    }

    // MARK: Tile appearance
    // Placeholder marks styled after each brand. Ship-ready official icons must
    // come from Google's brand resource pages (usage guidelines apply) — drop
    // them into Assets.xcassets and swap `systemImage` for an Image(named:).

    var systemImage: String {
        switch self {
        case .gmail:          return "envelope.fill"
        case .googleCalendar: return "calendar"
        }
    }

    var brandColor: Color {
        switch self {
        case .gmail:          return Color(red: 0.92, green: 0.26, blue: 0.21) // Gmail red
        case .googleCalendar: return Color(red: 0.26, green: 0.52, blue: 0.96) // Google blue
        }
    }
}
