import Foundation
import VoiceJournalCore

/// A catch-all destination that "logs" an entry into a typed bucket kept inside
/// the app itself: workouts, meals, and business ideas.
///
/// These are the categories that don't have an obvious first-party app to own
/// them (HealthKit meal/workout logging is possible but heavier, and there's no
/// system "ideas" app). Keeping them as structured in-app logs gives users an
/// immediate, browsable record — and each is a clean seam to later push into
/// HealthKit, Notes, or a third-party service.
struct LogDestination: Destination {
    let id: String
    let displayName: String
    let handledCategory: JournalCategory

    static let workout = LogDestination(id: "log.workout", displayName: "Workout Log", handledCategory: .workout)
    static let meal    = LogDestination(id: "log.meal",    displayName: "Meal Log",    handledCategory: .meal)
    static let idea    = LogDestination(id: "log.idea",    displayName: "Idea Inbox",  handledCategory: .businessIdea)

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == handledCategory
    }

    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult {
        // The entry already lives in the JournalStore, so "logging" here just
        // records that it was filed under this bucket. Downstream integrations
        // (HealthKit, Notes) would hook in at this point.
        .init(destinationID: id, destinationName: displayName, status: .success,
              detail: "Filed to \(displayName)")
    }
}

/// The fallback for free-form thoughts that don't match anything — they simply
/// stay in the journal as a note. Always "succeeds".
struct NoteDestination: Destination {
    let id = "note"
    let displayName = "Journal"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .note
    }

    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult {
        .init(destinationID: id, destinationName: displayName, status: .success,
              detail: "Kept as a note")
    }
}
