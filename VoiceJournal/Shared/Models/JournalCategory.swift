import Foundation

/// The high-level "bucket" a voice memo falls into. The categorizer maps free-form
/// speech onto one of these, and the router uses the category to decide where the
/// entry should end up (Reminders, Calendar, a workout log, etc.).
public enum JournalCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case businessIdea
    case task
    case schedule
    case workout
    case meal
    case note

    public var id: String { rawValue }

    /// Human-readable label shown in the UI.
    public var displayName: String {
        switch self {
        case .businessIdea: return "Business Idea"
        case .task:         return "Task"
        case .schedule:     return "Schedule"
        case .workout:      return "Workout"
        case .meal:         return "Meal"
        case .note:         return "Note"
        }
    }

    /// SF Symbol used to represent the category throughout the apps.
    public var systemImage: String {
        switch self {
        case .businessIdea: return "lightbulb"
        case .task:         return "checklist"
        case .schedule:     return "calendar"
        case .workout:      return "figure.run"
        case .meal:         return "fork.knife"
        case .note:         return "note.text"
        }
    }

    /// Categories the classifier is allowed to pick. `.note` is the fallback and is
    /// never chosen by keyword weight alone — it's what you get when nothing else scores.
    public static var classifiable: [JournalCategory] {
        [.businessIdea, .task, .schedule, .workout, .meal]
    }
}
