import Foundation

/// A single voice memo captured on the watch, plus everything the phone learns
/// about it (transcript, category, and where it was routed).
///
/// The entry travels through a pipeline:
/// 1. Watch records audio and creates the entry (transcript empty, category `.note`).
/// 2. Phone transcribes the audio and fills in `transcript`.
/// 3. Phone categorizes the transcript and fills in `category` / `confidence`.
/// 4. Phone routes the entry and appends `RoutingResult`s.
public struct JournalEntry: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let createdAt: Date

    /// Transcribed text. Empty until the phone runs transcription.
    public var transcript: String

    /// Best-guess category. Defaults to `.note` until classified.
    public var category: JournalCategory

    /// Classifier confidence in `category`, 0...1. Low confidence surfaces the
    /// entry for manual review instead of auto-routing.
    public var confidence: Double

    /// Dates the classifier pulled out of the text (e.g. "tomorrow at 3pm").
    /// Used to turn a scheduling memo into a real calendar event.
    public var detectedDates: [Date]

    /// Filename of the recorded audio inside the app's audio directory, if the
    /// recording was successfully transferred. Nil for text-only entries.
    public var audioFileName: String?

    /// Where this entry was sent, and whether each hand-off succeeded.
    public var routingResults: [RoutingResult]

    /// Whether the user has looked at and confirmed the automatic sorting.
    public var reviewed: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        transcript: String = "",
        category: JournalCategory = .note,
        confidence: Double = 0,
        detectedDates: [Date] = [],
        audioFileName: String? = nil,
        routingResults: [RoutingResult] = [],
        reviewed: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.transcript = transcript
        self.category = category
        self.confidence = confidence
        self.detectedDates = detectedDates
        self.audioFileName = audioFileName
        self.routingResults = routingResults
        self.reviewed = reviewed
    }

    /// A short preview for list rows.
    public var summary: String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Transcribing…" : trimmed
    }

    /// True when the classifier wasn't sure enough to trust the routing.
    public var needsReview: Bool {
        !reviewed && confidence < 0.5
    }
}
