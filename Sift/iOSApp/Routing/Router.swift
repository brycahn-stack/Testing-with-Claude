import Foundation
import SiftCore

/// Turns a classified entry into proposed actions. **Never** performs side
/// effects — that's `execute`, and it only runs after approval.
///
/// Destinations are tried in priority order; the first that both `canHandle`s
/// the entry and returns a proposal wins. A destination that returns nil is
/// declining (e.g. Google Calendar when it isn't connected), so the next one
/// gets a turn — that's how Google destinations shadow their Apple equivalents
/// only while connected.
public struct Router: Sendable {
    private let destinations: [Destination]
    private let confidenceThreshold: Double

    public init(
        destinations: [Destination]? = nil,
        confidenceThreshold: Double = KeywordCategorizer.reviewThreshold
    ) {
        // Order matters: connected destinations sit ahead of their local
        // equivalents and decline when disconnected.
        self.destinations = destinations ?? [
            // First, because "remember that I prefer mornings" would otherwise
            // read as a task. Its intent match is narrow enough to lead with.
            ObsidianProfileDestination(),
            // Same trick for "Sarah mentioned…" — ahead of the general note
            // destinations, gated on an equally narrow matcher.
            ObsidianPersonDestination(),
            GmailDestination(),
            GoogleCalendarDestination(),
            CalendarDestination(),
            RemindersDestination(),
            // Ahead of the in-app logs it replaces: ideas and notes go to the
            // vault when there is one, and to the log when there isn't.
            ObsidianDestination(),
            WorkoutDestination(),
            MealDestination(),
            LogDestination.idea,
            NoteDestination()
        ]
        self.confidenceThreshold = confidenceThreshold
    }

    /// Builds the proposals for an entry. Low-confidence classifications still
    /// produce a proposal — it just carries the low confidence forward, so the
    /// Review tab shows it and no trust setting will auto-approve it.
    public func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> [ProposedAction] {
        for destination in destinations where destination.canHandle(entry, result) {
            if let proposal = await destination.propose(entry, result) {
                return [proposal]
            }
        }
        return []
    }

    /// Runs an approved action against its destination.
    public func execute(_ action: ProposedAction) async -> RoutingResult {
        guard let destination = destinations.first(where: { $0.id == action.destinationID }) else {
            return .init(destinationID: action.destinationID, destinationName: action.destinationName,
                         status: .failed, detail: "No destination registered for \(action.destinationID)")
        }
        return await destination.execute(action)
    }

    /// True when a proposal is confident enough to be trusted at all.
    public func meetsConfidenceBar(_ action: ProposedAction) -> Bool {
        action.confidence >= confidenceThreshold
    }
}
