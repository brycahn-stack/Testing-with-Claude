import Foundation
import NaturalLanguage

/// The result of classifying a piece of text.
public struct CategorizationResult: Sendable {
    public let category: JournalCategory
    /// 0...1 confidence. Below `Categorizer.reviewThreshold` the entry is flagged
    /// for manual review rather than auto-routed.
    public let confidence: Double
    /// Dates extracted from the text ("tomorrow at 3", "next Monday").
    public let detectedDates: [Date]
    /// Matched keywords, kept for debugging / display.
    public let matchedKeywords: [String]

    public init(category: JournalCategory, confidence: Double, detectedDates: [Date] = [], matchedKeywords: [String] = []) {
        self.category = category
        self.confidence = confidence
        self.detectedDates = detectedDates
        self.matchedKeywords = matchedKeywords
    }
}

/// Anything that can turn free-form speech into a category + structured hints.
///
/// The app ships with `KeywordCategorizer` (fully on-device, deterministic, free).
/// Because this is a protocol, it can later be swapped for an LLM-backed
/// classifier without touching the routing or UI layers.
public protocol Categorizer: Sendable {
    func categorize(_ text: String) -> CategorizationResult
}

/// A lightweight, on-device classifier built on Apple's NaturalLanguage framework
/// plus weighted keyword scoring and `NSDataDetector` for dates.
///
/// It's intentionally simple and explainable: each category has a set of signal
/// phrases; the text is scored against all of them; the highest score wins. This
/// is a solid MVP baseline and an honest fallback for when a smarter model isn't
/// available.
public struct KeywordCategorizer: Categorizer {
    /// Confidence below this is treated as "not sure — ask the user".
    public static let reviewThreshold = 0.5

    /// Signal phrases per category. Multi-word phrases score higher than single
    /// words because they're less ambiguous.
    private static let signals: [JournalCategory: [String]] = [
        .businessIdea: [
            "business idea", "startup", "app idea", "product idea", "side project",
            "monetize", "revenue", "customers", "market", "pitch", "founder",
            "landing page", "mvp", "saas", "what if we built", "could sell"
        ],
        .task: [
            "remind me", "don't forget", "need to", "have to", "to-do", "todo",
            "pick up", "call", "email", "text", "buy", "order", "schedule a",
            "follow up", "make sure to", "i should"
        ],
        .schedule: [
            "meeting", "appointment", "calendar", "at 8", "at 9", "at 10",
            "am", "pm", "o'clock", "tomorrow", "tonight", "next week",
            "on monday", "on tuesday", "on wednesday", "on thursday",
            "on friday", "on saturday", "on sunday", "block off", "reschedule"
        ],
        .workout: [
            "workout", "exercise", "gym", "reps", "sets", "squat", "deadlift",
            "bench", "cardio", "run", "ran", "miles", "push-ups", "pushups",
            "pull-ups", "pullups", "lift", "training", "stretch", "rest day"
        ],
        .meal: [
            "ate", "eating", "breakfast", "lunch", "dinner", "snack", "meal",
            "calories", "protein", "carbs", "coffee", "smoothie", "grams of",
            "had a", "cooked", "recipe", "hungry"
        ]
    ]

    public init() {}

    public func categorize(_ text: String) -> CategorizationResult {
        let normalized = text.lowercased()
        let detectedDates = Self.detectDates(in: text)

        var scores: [JournalCategory: Double] = [:]
        var matched: [JournalCategory: [String]] = [:]

        for (category, phrases) in Self.signals {
            for phrase in phrases where normalized.contains(phrase) {
                // Multi-word phrases are stronger signals than lone words.
                let weight = phrase.contains(" ") ? 2.0 : 1.0
                scores[category, default: 0] += weight
                matched[category, default: []].append(phrase)
            }
        }

        // A concrete date/time is a strong "put this on the calendar" signal.
        if !detectedDates.isEmpty {
            scores[.schedule, default: 0] += 2.5
        }

        guard let (best, bestScore) = scores.max(by: { $0.value < $1.value }), bestScore > 0 else {
            // Nothing matched — it's a free-form thought.
            return CategorizationResult(category: .note, confidence: 0.2, detectedDates: detectedDates)
        }

        // A task that names a specific time is really a calendar event.
        var category = best
        if best == .task && !detectedDates.isEmpty {
            category = .schedule
        }

        let total = scores.values.reduce(0, +)
        // Confidence blends "how dominant was the winner" with "did it score at all".
        let dominance = bestScore / total
        let magnitude = min(1.0, bestScore / 4.0)
        let confidence = min(1.0, (dominance * 0.6) + (magnitude * 0.4))

        return CategorizationResult(
            category: category,
            confidence: confidence,
            detectedDates: detectedDates,
            matchedKeywords: matched[best] ?? []
        )
    }

    /// Pulls dates/times out of free text using the same detector the OS uses
    /// for data-detection links.
    static func detectDates(in text: String) -> [Date] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.date)
    }
}
