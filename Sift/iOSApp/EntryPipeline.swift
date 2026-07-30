import Foundation
import SiftCore

/// Orchestrates what happens to a memo once it reaches the phone:
/// transcribe → categorize → **propose** → (maybe auto-approve) → persist.
///
/// Note what it no longer does: perform side effects. Proposals land in the
/// `ProposalStore` and wait for the user, unless a destination they've explicitly
/// trusted clears the confidence bar. That makes the whole pipeline safe to run
/// unattended from a background wake.
@MainActor
final class EntryPipeline: ObservableObject {
    private let store: JournalStore
    private let proposals: ProposalStore
    private let trust: TrustSettings
    private let transcriber: Transcriber
    private let categorizer: Categorizer
    private let router: Router

    init(
        store: JournalStore,
        proposals: ProposalStore,
        trust: TrustSettings,
        transcriber: Transcriber = SpeechTranscriber(),
        categorizer: Categorizer = KeywordCategorizer(),
        router: Router = Router()
    ) {
        self.store = store
        self.proposals = proposals
        self.trust = trust
        self.transcriber = transcriber
        self.categorizer = categorizer
        self.router = router
    }

    /// Ingests a recording that just arrived from the watch.
    func ingest(id: UUID, fileURL: URL, createdAt: Date, watchTranscript: String?) async {
        let audioName = "\(id.uuidString).m4a"
        let destURL = store.audioDirectory.appendingPathComponent(audioName)
        try? FileManager.default.removeItem(at: destURL)
        let storedAudio = (try? FileManager.default.copyItem(at: fileURL, to: destURL)) != nil ? audioName : nil

        var entry = JournalEntry(id: id, createdAt: createdAt, audioFileName: storedAudio)
        store.add(entry)

        let transcript = await transcribeOrFallback(
            audioURL: storedAudio.map { store.audioDirectory.appendingPathComponent($0) },
            fallback: watchTranscript
        )
        entry.transcript = transcript
        store.update(entry)

        guard !transcript.isEmpty else { return }
        await classifyAndPropose(&entry)
    }

    /// Adds an entry typed directly into the phone.
    func ingestText(_ text: String) async {
        var entry = JournalEntry(transcript: text)
        store.add(entry)
        await classifyAndPropose(&entry)
    }

    /// Re-runs classification and proposing after the user edits or corrects an entry.
    func reprocess(_ entry: JournalEntry, overrideCategory: JournalCategory? = nil) async {
        // Clear stale proposals for this entry so we don't stack duplicates.
        for stale in proposals.proposals(forEntry: entry.id) where stale.status == .pending {
            proposals.remove(stale)
        }
        var updated = entry
        await classifyAndPropose(&updated, overrideCategory: overrideCategory)
    }

    /// Approve and run a proposal, recording the outcome.
    func approve(_ action: ProposedAction) async {
        var running = action
        running.status = .approved
        proposals.update(running)

        let result = await router.execute(running)
        running.result = result
        running.status = result.status == .failed ? .failed : .completed
        proposals.update(running)

        // Mirror the outcome onto the journal entry for the detail view.
        if var entry = store.entry(withID: action.entryID) {
            entry.routingResults.removeAll { $0.destinationID == result.destinationID }
            entry.routingResults.append(result)
            entry.reviewed = true
            store.update(entry)
        }
    }

    func dismiss(_ action: ProposedAction) {
        var updated = action
        updated.status = .dismissed
        proposals.update(updated)
    }

    // MARK: - Internals

    private func classifyAndPropose(_ entry: inout JournalEntry, overrideCategory: JournalCategory? = nil) async {
        let classification = categorizer.categorize(entry.transcript)
        let category = overrideCategory ?? classification.category
        let effective = CategorizationResult(
            category: category,
            confidence: overrideCategory != nil ? 1.0 : classification.confidence,
            detectedDates: classification.detectedDates,
            matchedKeywords: classification.matchedKeywords
        )

        entry.category = category
        entry.confidence = effective.confidence
        entry.detectedDates = classification.detectedDates
        entry.reviewed = overrideCategory != nil
        store.update(entry)

        let proposed = await router.propose(entry, effective)
        proposals.add(contentsOf: proposed)

        // Anything the user has explicitly trusted, and that clears the
        // confidence bar, runs without waiting. Sends and invites never do.
        for action in proposed where trust.canAutoApprove(action) && router.meetsConfidenceBar(action) {
            await approve(action)
        }
    }

    private func transcribeOrFallback(audioURL: URL?, fallback: String?) async -> String {
        if let audioURL,
           let text = try? await transcriber.transcribe(fileURL: audioURL), !text.isEmpty {
            return text
        }
        return fallback ?? ""
    }
}
