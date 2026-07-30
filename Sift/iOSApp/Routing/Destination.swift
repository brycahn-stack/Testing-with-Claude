import Foundation
import SiftCore

/// A place a journal entry can be sent: Reminders, Calendar, a workout log, an
/// idea inbox, etc. Adding a new integration means writing one conformance and
/// registering it with the `Router` — nothing else changes.
public protocol Destination: Sendable {
    /// Stable identifier stored on `RoutingResult`.
    var id: String { get }
    /// User-facing name, e.g. "Reminders".
    var displayName: String { get }

    /// Whether this destination wants to handle the entry given its classification.
    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool

    /// Perform the hand-off. Should never throw — surface problems as a
    /// `.failed` result so one broken integration can't block the others.
    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult
}
