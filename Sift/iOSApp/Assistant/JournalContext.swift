import Foundation
import SiftCore

/// Everything the assistant is allowed to read: the full journal.
///
/// This is the single choke point for AI access to your notes — one place to
/// audit, and one place to add redaction or per-category opt-outs later. It also
/// keeps the responder ignorant of storage details, so swapping the local
/// responder for an on-device or cloud model changes nothing here.
public struct JournalContext: Sendable {
    public let entries: [JournalEntry]
    public let pendingProposals: [ProposedAction]

    public init(entries: [JournalEntry], pendingProposals: [ProposedAction] = []) {
        self.entries = entries
        self.pendingProposals = pendingProposals
    }

    // MARK: Retrieval helpers

    public func entries(in category: JournalCategory) -> [JournalEntry] {
        entries.filter { $0.category == category }
    }

    public func entries(since date: Date) -> [JournalEntry] {
        entries.filter { $0.createdAt >= date }
    }

    /// Naive keyword search — every term must appear. Good enough for the local
    /// responder, and the exact place to swap in embeddings later.
    public func search(_ query: String) -> [JournalEntry] {
        let terms = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !Self.stopWords.contains($0) }
        guard !terms.isEmpty else { return [] }
        return entries.filter { entry in
            let text = entry.transcript.lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    /// Compact digest suitable for a model prompt, newest first and capped so it
    /// fits a small on-device context window.
    public func digest(limit: Int = 60) -> String {
        entries.prefix(limit).map { entry in
            let date = entry.createdAt.formatted(date: .abbreviated, time: .shortened)
            return "[\(date)] (\(entry.category.displayName)) \(entry.transcript)"
        }.joined(separator: "\n")
    }

    public var isEmpty: Bool { entries.isEmpty }

    private static let stopWords: Set<String> = [
        "what", "when", "did", "the", "and", "for", "have", "any", "was", "were",
        "about", "with", "that", "this", "you", "my", "me", "all", "show", "tell"
    ]
}

/// A reply from the assistant: prose, plus any actions it wants to propose.
/// Actions still go through the Review queue — the assistant proposes, it never
/// executes.
public struct AssistantReply: Sendable {
    public let text: String
    public let citedEntryIDs: [UUID]
    public let proposedActions: [ProposedAction]

    public init(text: String, citedEntryIDs: [UUID] = [], proposedActions: [ProposedAction] = []) {
        self.text = text
        self.citedEntryIDs = citedEntryIDs
        self.proposedActions = proposedActions
    }
}

/// Anything that can answer questions about the journal.
///
/// Ships with `LocalQueryResponder` (deterministic, on-device, free). The planned
/// replacement is Apple's Foundation Models framework, which runs a model
/// on-device with structured output — meaning journal contents never leave the
/// phone. A cloud model would be an explicit opt-in, not a default.
public protocol AssistantResponder: Sendable {
    func respond(to question: String, context: JournalContext) async -> AssistantReply
}

/// A deterministic responder that answers the common question shapes by querying
/// the journal directly. Not a language model — it recognizes intents and reports
/// real data, so the tab is useful before any model is wired up, and remains the
/// offline fallback afterwards.
public struct LocalQueryResponder: AssistantResponder {
    public init() {}

    public func respond(to question: String, context: JournalContext) async -> AssistantReply {
        let q = question.lowercased()

        guard !context.isEmpty else {
            return AssistantReply(text: "Your journal is empty so far. Record something on your watch and I'll have something to work with.")
        }

        // "what's waiting on me?"
        if q.contains("waiting") || q.contains("pending") || q.contains("to approve") {
            let count = context.pendingProposals.count
            guard count > 0 else { return AssistantReply(text: "Nothing waiting — your review queue is clear.") }
            let list = context.pendingProposals.prefix(5)
                .map { "• \($0.payload.headline)" }
                .joined(separator: "\n")
            return AssistantReply(text: "You have \(count) action\(count == 1 ? "" : "s") waiting:\n\n\(list)")
        }

        // Category round-ups: "what business ideas have I had?"
        if let category = matchedCategory(in: q) {
            let window = timeWindow(in: q)
            var matches = context.entries(in: category)
            if let window { matches = matches.filter { $0.createdAt >= window.start } }
            guard !matches.isEmpty else {
                return AssistantReply(text: "No \(category.displayName.lowercased()) entries\(window.map { " \($0.label)" } ?? "") yet.")
            }
            let list = matches.prefix(10).map { "• \($0.summary)" }.joined(separator: "\n")
            let scope = window.map { " \($0.label)" } ?? ""
            return AssistantReply(
                text: "\(matches.count) \(category.displayName.lowercased()) entr\(matches.count == 1 ? "y" : "ies")\(scope):\n\n\(list)",
                citedEntryIDs: matches.prefix(10).map(\.id)
            )
        }

        // Counts and summaries: "summarize my week"
        if q.contains("summar") || q.contains("overview") || q.contains("how many") {
            let window = timeWindow(in: q) ?? (start: Date().addingTimeInterval(-7 * 86400), label: "this past week")
            let recent = context.entries(since: window.start)
            guard !recent.isEmpty else { return AssistantReply(text: "Nothing logged \(window.label).") }
            let counts = Dictionary(grouping: recent, by: \.category)
                .map { "• \($0.value.count) × \($0.key.displayName)" }
                .sorted()
                .joined(separator: "\n")
            return AssistantReply(
                text: "\(recent.count) entries \(window.label):\n\n\(counts)",
                citedEntryIDs: recent.map(\.id)
            )
        }

        // Fall back to search.
        let hits = context.search(question)
        guard !hits.isEmpty else {
            return AssistantReply(text: "I couldn't find anything about that. Try asking about a category — business ideas, tasks, workouts, meals — or ask me to summarize your week.")
        }
        let list = hits.prefix(8).map { entry in
            "• [\(entry.createdAt.formatted(date: .abbreviated, time: .omitted))] \(entry.summary)"
        }.joined(separator: "\n")
        return AssistantReply(
            text: "Found \(hits.count) matching entr\(hits.count == 1 ? "y" : "ies"):\n\n\(list)",
            citedEntryIDs: hits.prefix(8).map(\.id)
        )
    }

    private func matchedCategory(in q: String) -> JournalCategory? {
        if q.contains("business") || q.contains("idea")   { return .businessIdea }
        if q.contains("workout") || q.contains("exercise") || q.contains("gym") { return .workout }
        if q.contains("meal") || q.contains("ate") || q.contains("food") || q.contains("eat") { return .meal }
        if q.contains("task") || q.contains("to-do") || q.contains("todo") { return .task }
        if q.contains("meeting") || q.contains("schedule") || q.contains("calendar") { return .schedule }
        return nil
    }

    private func timeWindow(in q: String) -> (start: Date, label: String)? {
        if q.contains("today")      { return (Calendar.current.startOfDay(for: Date()), "today") }
        if q.contains("this week") || q.contains("past week") || q.contains("last week") {
            return (Date().addingTimeInterval(-7 * 86400), "this past week")
        }
        if q.contains("this month") || q.contains("past month") {
            return (Date().addingTimeInterval(-30 * 86400), "this past month")
        }
        return nil
    }
}
