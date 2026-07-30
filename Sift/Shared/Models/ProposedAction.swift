import Foundation

/// A concrete, editable thing Sift wants to do with a journal entry — send an
/// email, create an event, log a workout. Proposals are **never** executed until
/// the user approves them (or a destination they've explicitly trusted
/// auto-approves).
///
/// This is the seam the AI assistant plugs into: today the keyword categorizer
/// produces proposals, later a model produces richer ones, and neither ever
/// touches Gmail or Calendar directly.
public struct ProposedAction: Codable, Identifiable, Hashable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending      // waiting on the user
        case approved     // user said yes, not yet run
        case completed    // executed successfully
        case dismissed    // user said no
        case failed       // execution errored
    }

    public let id: UUID
    /// The journal entry this came from.
    public let entryID: UUID
    public let destinationID: String
    public let destinationName: String
    /// What will happen — editable by the user before approving.
    public var payload: ActionPayload
    public var status: Status
    /// Plain-language "why I think this" shown under the card.
    public var reasoning: String?
    /// 0...1 — drives whether a trusted destination may auto-approve.
    public var confidence: Double
    public let createdAt: Date
    /// Filled in once executed.
    public var result: RoutingResult?

    public init(
        id: UUID = UUID(),
        entryID: UUID,
        destinationID: String,
        destinationName: String,
        payload: ActionPayload,
        status: Status = .pending,
        reasoning: String? = nil,
        confidence: Double = 0,
        createdAt: Date = Date(),
        result: RoutingResult? = nil
    ) {
        self.id = id
        self.entryID = entryID
        self.destinationID = destinationID
        self.destinationName = destinationName
        self.payload = payload
        self.status = status
        self.reasoning = reasoning
        self.confidence = confidence
        self.createdAt = createdAt
        self.result = result
    }

    public var isOutstanding: Bool { status == .pending || status == .approved }

    /// Actions that leave the device and are seen by other people always warrant
    /// an explicit look, no matter how confident the proposer is.
    public var isHighStakes: Bool {
        switch payload {
        case .email(let d):        return d.sendImmediately
        case .calendarEvent(let d): return !d.invitees.isEmpty
        default:                    return false
        }
    }
}

/// The typed, editable body of a proposed action. Structured rather than free
/// text so the confirmation UI can render a real preview and the user can fix
/// individual fields before committing.
public enum ActionPayload: Codable, Hashable, Sendable {
    case email(EmailDraft)
    case calendarEvent(CalendarEventDraft)
    case reminder(ReminderDraft)
    case logEntry(LogDraft)
    case note(NoteDraft)
}

// MARK: - Payload types

public struct EmailDraft: Codable, Hashable, Sendable {
    /// Verified recipient addresses. Deliberately starts empty — see
    /// `recipientHint`. Send stays disabled until this has a valid address.
    public var to: [String]
    public var cc: [String]
    public var subject: String
    public var body: String
    /// The name Sift heard ("Sarah"), which is *not* an address. Shown as a
    /// prompt so the user supplies the real one — guessing an address is how you
    /// email the wrong person.
    public var recipientHint: String?
    /// True = send on approval; false = save to Gmail drafts instead.
    public var sendImmediately: Bool

    public init(to: [String] = [], cc: [String] = [], subject: String, body: String,
                recipientHint: String? = nil, sendImmediately: Bool = true) {
        self.to = to
        self.cc = cc
        self.subject = subject
        self.body = body
        self.recipientHint = recipientHint
        self.sendImmediately = sendImmediately
    }

    /// A minimally valid address check — enough to stop obvious mistakes.
    public var hasValidRecipient: Bool {
        to.contains { $0.contains("@") && $0.contains(".") && !$0.hasSuffix("@") }
    }
}

public struct CalendarEventDraft: Codable, Hashable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var location: String?
    public var notes: String?
    public var isAllDay: Bool
    public var invitees: [String]

    public init(title: String, start: Date, end: Date, location: String? = nil,
                notes: String? = nil, isAllDay: Bool = false, invitees: [String] = []) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
        self.invitees = invitees
    }
}

public struct ReminderDraft: Codable, Hashable, Sendable {
    public var title: String
    public var notes: String?
    public var dueDate: Date?

    public init(title: String, notes: String? = nil, dueDate: Date? = nil) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
    }
}

/// Workout / meal / idea logs. `fields` holds whatever structure the proposer
/// managed to extract (sets, reps, calories) so richer extraction can land later
/// without a model change.
public struct LogDraft: Codable, Hashable, Sendable {
    public var kind: JournalCategory
    public var summary: String
    public var fields: [String: String]

    public init(kind: JournalCategory, summary: String, fields: [String: String] = [:]) {
        self.kind = kind
        self.summary = summary
        self.fields = fields
    }
}

public struct NoteDraft: Codable, Hashable, Sendable {
    public var title: String
    public var body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

// MARK: - Display helpers

public extension ActionPayload {
    /// One-line summary for compact rows and notifications.
    var headline: String {
        switch self {
        case .email(let d):
            return d.sendImmediately ? "Send email: \(d.subject)" : "Save draft: \(d.subject)"
        case .calendarEvent(let d):
            return "Create event: \(d.title)"
        case .reminder(let d):
            return "Add reminder: \(d.title)"
        case .logEntry(let d):
            return "Log \(d.kind.displayName.lowercased()): \(d.summary)"
        case .note(let d):
            return "Keep note: \(d.title)"
        }
    }

    var systemImage: String {
        switch self {
        case .email:         return "envelope.fill"
        case .calendarEvent: return "calendar"
        case .reminder:      return "checklist"
        case .logEntry(let d): return d.kind.systemImage
        case .note:          return "note.text"
        }
    }

    /// Label for the confirm button — says exactly what will happen.
    var commitVerb: String {
        switch self {
        case .email(let d):  return d.sendImmediately ? "Send" : "Save Draft"
        case .calendarEvent: return "Create Event"
        case .reminder:      return "Add Reminder"
        case .logEntry:      return "Log It"
        case .note:          return "Save Note"
        }
    }
}
