import Foundation
import SiftCore

/// Orchestrates what happens to a memo once it reaches the phone:
/// transcribe → categorize → route → persist. This is the heart of the app.
@MainActor
final class EntryPipeline: ObservableObject {
    private let store: JournalStore
    private let transcriber: Transcriber
    private let categorizer: Categorizer
    private let router: Router

    init(
        store: JournalStore,
        transcriber: Transcriber = SpeechTranscriber(),
        categorizer: Categorizer = KeywordCategorizer(),
        router: Router = Router()
    ) {
        self.store = store
        self.transcriber = transcriber
        self.categorizer = categorizer
        self.router = router
    }

    /// Ingests a recording that just arrived from the watch.
    /// - Parameters:
    ///   - fileURL: temporary location of the transferred audio; it's copied into
    ///     the store's audio directory.
    ///   - watchTranscript: optional transcript captured on the watch; used as a
    ///     fallback if on-phone transcription fails.
    func ingest(id: UUID, fileURL: URL, createdAt: Date, watchTranscript: String?) async {
        // Persist the audio under a stable name and show the entry immediately.
        let audioName = "\(id.uuidString).m4a"
        let destURL = store.audioDirectory.appendingPathComponent(audioName)
        try? FileManager.default.removeItem(at: destURL)
        let storedAudio = (try? FileManager.default.copyItem(at: fileURL, to: destURL)) != nil ? audioName : nil

        var entry = JournalEntry(id: id, createdAt: createdAt, audioFileName: storedAudio)
        store.add(entry)

        // Transcribe (fall back to whatever the watch heard).
        let transcript = await transcribeOrFallback(audioURL: storedAudio.map { store.audioDirectory.appendingPathComponent($0) },
                                                     fallback: watchTranscript)
        entry.transcript = transcript
        store.update(entry)

        guard !transcript.isEmpty else { return }

        // Classify and route.
        let classification = categorizer.categorize(transcript)
        entry.category = classification.category
        entry.confidence = classification.confidence
        entry.detectedDates = classification.detectedDates
        entry.routingResults = await router.route(entry, classification)
        entry.reviewed = !entry.needsReview
        store.update(entry)
    }

    /// Re-runs classification and routing after the user edits a transcript or
    /// corrects a category.
    func reprocess(_ entry: JournalEntry, overrideCategory: JournalCategory? = nil) async {
        var updated = entry
        let classification = categorizer.categorize(entry.transcript)
        let category = overrideCategory ?? classification.category
        updated.category = category
        updated.confidence = overrideCategory != nil ? 1.0 : classification.confidence
        updated.detectedDates = classification.detectedDates

        let effective = CategorizationResult(
            category: category,
            confidence: updated.confidence,
            detectedDates: classification.detectedDates,
            matchedKeywords: classification.matchedKeywords
        )
        updated.routingResults = await router.route(updated, effective)
        updated.reviewed = true
        store.update(updated)
    }

    private func transcribeOrFallback(audioURL: URL?, fallback: String?) async -> String {
        if let audioURL {
            if let text = try? await transcriber.transcribe(fileURL: audioURL), !text.isEmpty {
                return text
            }
        }
        return fallback ?? ""
    }
}
