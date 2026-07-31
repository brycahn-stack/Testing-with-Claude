import Foundation
import SiftCore

/// A catch-all destination that "logs" an entry into a typed bucket kept inside
/// the app itself.
///
/// Only business ideas still land here: there's no system "ideas" app, and when
/// no Obsidian vault is connected this is where they go. Training and meals
/// graduated to `WorkoutDestination` and `MealDestination`, which write
/// structured records into the Health store instead of a bare summary line.
struct LogDestination: Destination {
    let id: String
    let displayName: String
    let handledCategory: JournalCategory

    static let idea = LogDestination(id: "log.idea", displayName: "Idea Inbox", handledCategory: .businessIdea)

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == handledCategory
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .logEntry(LogDraft(
                kind: handledCategory,
                summary: TitleBuilder.cleanTitle(from: entry.transcript, maxWords: 12),
                // Structured fields land here once a model does the extraction
                // (sets/reps, calories/macros). Empty for the keyword proposer.
                fields: [:]
            )),
            reasoning: "Matched \(handledCategory.displayName.lowercased()) language.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        // The entry already lives in the JournalStore, so "logging" here records
        // that it was filed under this bucket. HealthKit/Notes hook in at this point.
        .init(destinationID: id, destinationName: displayName, status: .success,
              detail: "Filed to \(displayName)")
    }
}

/// The fallback for free-form thoughts that don't match anything — they simply
/// stay in the journal as a note.
struct NoteDestination: Destination {
    let id = "note"
    let displayName = "Journal"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .note
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .note(NoteDraft(
                title: TitleBuilder.cleanTitle(from: entry.transcript),
                body: entry.transcript
            )),
            reasoning: "No clear action — keeping it as a note.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        .init(destinationID: id, destinationName: displayName, status: .success,
              detail: "Kept as a note")
    }
}
