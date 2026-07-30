import Foundation
import VoiceJournalCore

/// Creates a Gmail **draft** (never auto-sends) from memos that sound like email
/// intent: "email Sarah about the pitch deck". The user reviews and sends from
/// Gmail — the same commit-or-dismiss philosophy as the rest of the app.
struct GmailDraftDestination: Destination {
    let id = "google.gmail"
    let displayName = "Gmail"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        // Only claim entries with explicit email intent; connection is checked in
        // route() so a disconnected service reports a helpful failure.
        let text = entry.transcript.lowercased()
        return result.category == .task && (text.contains("email ") || text.contains("send an email"))
    }

    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult {
        guard await GoogleAuthStore.shared.isConnected(.gmail) else {
            // Not connected — pass through so the memo becomes a Reminder instead.
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: RouterPassthrough.marker)
        }
        do {
            let token = try await GoogleAuthStore.shared.validAccessToken(for: .gmail)
            let subject = TitleBuilder.cleanTitle(from: entry.transcript)

            // RFC 2822 message, base64url-encoded, recipient left blank on purpose —
            // the user fills it in when reviewing the draft in Gmail.
            let rfc822 = "To: \r\nSubject: \(subject)\r\nContent-Type: text/plain; charset=utf-8\r\n\r\n\(entry.transcript)\r\n\r\n— drafted from a Voice Journal memo"
            let raw = Data(rfc822.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")

            var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/drafts")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["message": ["raw": raw]])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw GoogleAuthError.httpError(
                    (response as? HTTPURLResponse)?.statusCode ?? -1,
                    String(data: data, encoding: .utf8) ?? ""
                )
            }

            let draftID = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
            return .init(destinationID: id, destinationName: displayName, status: .needsConfirmation,
                         detail: "Gmail draft: \(subject) — open Gmail to finish & send",
                         externalID: draftID)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }
}

/// Sends scheduling memos to Google Calendar. Registered ahead of the local
/// `CalendarDestination` in the router, so when the user has connected Google
/// Calendar it wins; when not connected it declines and the local one takes over.
struct GoogleCalendarDestination: Destination {
    let id = "google.calendar"
    let displayName = "Google Calendar"

    /// Checked synchronously via the published UI state mirror so `canHandle`
    /// stays non-async; the authoritative check happens in `route()`.
    let isConnected: @Sendable () async -> Bool

    init(isConnected: @escaping @Sendable () async -> Bool = { await GoogleAuthStore.shared.isConnected(.googleCalendar) }) {
        self.isConnected = isConnected
    }

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .schedule && !result.detectedDates.isEmpty
    }

    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult {
        guard await isConnected() else {
            // Signal "pass" so the Router falls through to the local calendar.
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: RouterPassthrough.marker)
        }
        guard let start = result.detectedDates.first else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "No date detected")
        }
        do {
            let token = try await GoogleAuthStore.shared.validAccessToken(for: .googleCalendar)
            let formatter = ISO8601DateFormatter()
            let body: [String: Any] = [
                "summary": TitleBuilder.cleanTitle(from: entry.transcript),
                "description": "\(entry.transcript)\n\n— from a Voice Journal memo",
                "start": ["dateTime": formatter.string(from: start)],
                "end": ["dateTime": formatter.string(from: start.addingTimeInterval(3600))]
            ]

            var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!)
            request.httpMethod = "POST"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw GoogleAuthError.httpError(
                    (response as? HTTPURLResponse)?.statusCode ?? -1,
                    String(data: data, encoding: .utf8) ?? ""
                )
            }

            let eventID = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
            return .init(destinationID: id, destinationName: displayName, status: .needsConfirmation,
                         detail: "Google Calendar: \(TitleBuilder.cleanTitle(from: entry.transcript)) @ \(start.formatted(date: .abbreviated, time: .shortened))",
                         externalID: eventID)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }
}

/// Sentinel a destination can return to mean "not applicable right now — let the
/// next destination try" (e.g. Google Calendar when it isn't connected).
enum RouterPassthrough {
    static let marker = "__passthrough__"
}
