import Foundation
import SiftCore

/// Composes an email from memos with email intent ("email Sarah about the pitch
/// deck") and — once the user confirms in the preview — either **sends** it or
/// saves it to Gmail drafts.
///
/// Nothing is sent without an explicit tap: `isHighStakes` is true for sends, so
/// the trust setting can't auto-approve one. The proposal also deliberately
/// leaves the recipient address empty (only a name hint), which means the
/// confirmation sheet is where a human supplies who actually receives this.
struct GmailDestination: Destination {
    let id = "google.gmail"
    let displayName = "Gmail"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        let text = entry.transcript.lowercased()
        return result.category == .task && (text.contains("email") || text.contains("send a note to"))
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        // Not connected — decline so the memo becomes a Reminder instead.
        guard await GoogleAuthStore.shared.isConnected(.gmail) else { return nil }

        let hint = TitleBuilder.recipientHint(from: entry.transcript)
        return ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .email(EmailDraft(
                subject: TitleBuilder.cleanTitle(from: entry.transcript),
                body: entry.transcript,
                recipientHint: hint,
                sendImmediately: true
            )),
            reasoning: hint.map { "Sounds like an email to \($0)." } ?? "Sounds like an email.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        guard case .email(let draft) = action.payload else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Wrong payload type")
        }
        guard draft.hasValidRecipient else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "No recipient address")
        }
        do {
            let token = try await GoogleAuthStore.shared.validAccessToken(for: .gmail)
            let raw = Self.rfc2822(draft)

            // Sending and drafting are the same payload, different endpoints.
            let endpoint = draft.sendImmediately
                ? "https://gmail.googleapis.com/gmail/v1/users/me/messages/send"
                : "https://gmail.googleapis.com/gmail/v1/users/me/drafts"
            let body: [String: Any] = draft.sendImmediately
                ? ["raw": raw]
                : ["message": ["raw": raw]]

            var request = URLRequest(url: URL(string: endpoint)!)
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

            let messageID = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["id"] as? String
            let verb = draft.sendImmediately ? "Sent to" : "Draft saved for"
            return .init(destinationID: id, destinationName: displayName, status: .success,
                         detail: "\(verb) \(draft.to.joined(separator: ", ")) — \(draft.subject)",
                         externalID: messageID)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }

    /// RFC 2822 message, base64url-encoded as the Gmail API expects.
    private static func rfc2822(_ draft: EmailDraft) -> String {
        var lines = ["To: \(draft.to.joined(separator: ", "))"]
        if !draft.cc.isEmpty { lines.append("Cc: \(draft.cc.joined(separator: ", "))") }
        lines.append("Subject: \(draft.subject)")
        lines.append("Content-Type: text/plain; charset=utf-8")
        lines.append("")
        lines.append(draft.body)

        return Data(lines.joined(separator: "\r\n").utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Creates events on the user's primary Google Calendar. Sits ahead of the local
/// `CalendarDestination` in the router and declines when not connected, so
/// scheduling memos fall back to Apple Calendar automatically.
struct GoogleCalendarDestination: Destination {
    let id = "google.calendar"
    let displayName = "Google Calendar"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .schedule && !result.detectedDates.isEmpty
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        guard await GoogleAuthStore.shared.isConnected(.googleCalendar) else { return nil }
        guard let start = result.detectedDates.first else { return nil }

        return ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .calendarEvent(CalendarEventDraft(
                title: TitleBuilder.cleanTitle(from: entry.transcript),
                start: start,
                end: start.addingTimeInterval(3600),
                notes: entry.transcript
            )),
            reasoning: "Heard a specific time, so this looks like a calendar event.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        guard case .calendarEvent(let draft) = action.payload else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Wrong payload type")
        }
        do {
            let token = try await GoogleAuthStore.shared.validAccessToken(for: .googleCalendar)
            let formatter = ISO8601DateFormatter()

            var body: [String: Any] = [
                "summary": draft.title,
                "description": draft.notes ?? "",
                "start": ["dateTime": formatter.string(from: draft.start)],
                "end": ["dateTime": formatter.string(from: draft.end)]
            ]
            if let location = draft.location, !location.isEmpty { body["location"] = location }
            if !draft.invitees.isEmpty {
                body["attendees"] = draft.invitees.map { ["email": $0] }
            }

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
            return .init(destinationID: id, destinationName: displayName, status: .success,
                         detail: "\(draft.title) — \(draft.start.formatted(date: .abbreviated, time: .shortened))",
                         externalID: eventID)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }
}
