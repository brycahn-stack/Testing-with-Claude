import Foundation
import SiftCore

/// Decides where a classified entry goes and executes the hand-off.
///
/// Destinations are tried in priority order; the first that `canHandle` the entry
/// wins. Low-confidence classifications are held back for manual review instead of
/// being auto-routed to the wrong place.
public struct Router: Sendable {
    private let destinations: [Destination]
    private let confidenceThreshold: Double

    public init(
        destinations: [Destination]? = nil,
        confidenceThreshold: Double = KeywordCategorizer.reviewThreshold
    ) {
        // Order matters: more specific / higher-value destinations first.
        // Google destinations sit ahead of their local equivalents — they defer
        // (pass through) when the service isn't connected.
        self.destinations = destinations ?? [
            GmailDraftDestination(),
            GoogleCalendarDestination(),
            CalendarDestination(),
            RemindersDestination(),
            LogDestination.workout,
            LogDestination.meal,
            LogDestination.idea,
            NoteDestination()
        ]
        self.confidenceThreshold = confidenceThreshold
    }

    /// Routes the entry, returning the results to store on it. When confidence is
    /// low, returns a single `needsConfirmation` result and skips side effects so
    /// nothing lands in the wrong app without the user's blessing.
    public func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> [RoutingResult] {
        guard result.confidence >= confidenceThreshold else {
            return [RoutingResult(
                destinationID: "review",
                destinationName: "Needs Review",
                status: .needsConfirmation,
                detail: "Not sure where this goes (\(result.category.displayName), \(Int(result.confidence * 100))% confident)"
            )]
        }

        for destination in destinations where destination.canHandle(entry, result) {
            let routed = await destination.route(entry, result)
            // A passthrough means "not applicable right now" (e.g. Google Calendar
            // not connected) — fall through to the next destination.
            if routed.status == .failed && routed.detail == RouterPassthrough.marker {
                continue
            }
            return [routed]
        }
        return []
    }
}
