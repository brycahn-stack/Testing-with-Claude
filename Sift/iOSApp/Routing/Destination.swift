import Foundation
import SiftCore

/// A place a journal entry can be sent: Gmail, Calendar, Reminders, a log.
///
/// Split deliberately into two phases:
/// - `propose` builds a typed, editable `ProposedAction` and has **no side
///   effects** — safe to run on every entry, including from a background wake.
/// - `execute` performs the real hand-off, and only ever runs after the user
///   approves (or a destination they've trusted auto-approves).
///
/// That split is what makes an AI proposer safe: a hallucinated proposal is a
/// card you dismiss, not an email someone already received.
public protocol Destination: Sendable {
    /// Stable identifier stored on proposals and results.
    var id: String { get }
    /// User-facing name, e.g. "Gmail".
    var displayName: String { get }

    /// Whether this destination wants to handle the entry given its classification.
    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool

    /// Build the proposed action. Return nil to decline (e.g. the service isn't
    /// connected) so the router falls through to the next destination.
    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction?

    /// Carry out an approved action. Should never throw — surface problems as a
    /// `.failed` result so one broken integration can't block the others.
    func execute(_ action: ProposedAction) async -> RoutingResult
}

/// Small helper to make a tidy title from a raw transcript.
public enum TitleBuilder {
    public static func cleanTitle(from transcript: String, maxWords: Int = 8) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common lead-ins so "remind me to call mom" becomes "Call mom".
        for prefix in ["remind me to ", "remind me ", "i need to ", "i have to ",
                       "don't forget to ", "note to self "] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        let words = text.split(separator: " ").prefix(maxWords).joined(separator: " ")
        let title = words.isEmpty ? text : words
        return title.prefix(1).uppercased() + title.dropFirst()
    }

    /// Pulls a likely recipient name out of "email Sarah about the deck".
    /// Returns a *name*, never an address — resolving it to a real address is
    /// the user's job in the confirmation sheet.
    public static func recipientHint(from transcript: String) -> String? {
        let pattern = #"(?:email|e-mail|message|write)\s+([A-Z][a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: transcript,
                  range: NSRange(transcript.startIndex..., in: transcript)
              ),
              let range = Range(match.range(at: 1), in: transcript)
        else { return nil }
        return String(transcript[range])
    }
}
