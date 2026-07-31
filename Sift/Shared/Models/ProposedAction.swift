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
        // Creating a new note is additive and reversible; *editing* a file the
        // user already wrote is not, so appends always get a look.
        case .markdownNote(let d): return d.mode.isAppend
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
    case markdownNote(MarkdownNoteDraft)
    case workoutLog(WorkoutDraft)
    case mealLog(MealDraft)
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

/// A training session headed for Sift's own Health store.
///
/// Structured rather than a text blob because the whole point is that sets and
/// reps have nowhere else to live — Apple Health has no data type for them.
/// `transcript` is always kept, so a session the extractor couldn't parse still
/// shows the words that were said.
public struct WorkoutDraft: Codable, Hashable, Sendable {
    public var exercises: [LoggedExercise]
    public var transcript: String
    public var date: Date

    public init(exercises: [LoggedExercise] = [], transcript: String, date: Date = Date()) {
        self.exercises = exercises
        self.transcript = transcript
        self.date = date
    }

    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// "Squat, Bench Press" — what the card shows at a glance.
    public var exerciseNames: String {
        exercises.map(\.name).joined(separator: ", ")
    }
}

/// A meal headed for the Health store — and, once macros can be extracted
/// reliably, for HealthKit as an `HKCorrelation` of type `.food`.
public struct MealDraft: Codable, Hashable, Sendable {
    public var summary: String
    public var transcript: String
    public var nutrition: Nutrition
    public var date: Date

    public init(summary: String, transcript: String, nutrition: Nutrition = Nutrition(), date: Date = Date()) {
        self.summary = summary
        self.transcript = transcript
        self.nutrition = nutrition
        self.date = date
    }
}

/// A Markdown file destined for an Obsidian vault.
///
/// Two shapes, because they carry very different risk: **creating** a note only
/// adds a file, while **appending** rewrites something the user already owns.
/// The second is `isHighStakes`, so it never auto-approves.
///
/// The struct owns the rendering (`renderedNote` / `renderedAppendix`) so the
/// confirmation sheet previews the *exact* bytes that will land on disk — no
/// second code path that could disagree with what actually gets written.
public struct MarkdownNoteDraft: Codable, Hashable, Sendable {
    public enum Mode: Codable, Hashable, Sendable {
        /// Write a new note. The vault never overwrites — a clashing name gets
        /// a numeric suffix instead.
        case createNote
        /// Add a bullet to a note that already exists, under `heading`
        /// (created at the end of the file if it isn't there yet).
        case appendToNote(heading: String)

        public var isAppend: Bool {
            if case .appendToNote = self { return true }
            return false
        }

        public var heading: String? {
            if case .appendToNote(let heading) = self { return heading }
            return nil
        }
    }

    public var mode: Mode
    /// Vault-relative folder, e.g. "Sift". Empty means the vault root.
    public var folder: String
    /// Note name without the `.md` extension — also the H1 of a new note.
    public var noteName: String
    /// The prose. For an append this is the single fact being added.
    public var body: String
    /// Obsidian tags, without the leading `#`.
    public var tags: [String]
    /// Names of notes that already exist in the vault, rendered as `[[wikilinks]]`.
    public var links: [String]
    /// Extra YAML frontmatter, rendered in sorted key order for stable diffs.
    public var frontmatter: [String: String]
    public var date: Date

    public init(
        mode: Mode = .createNote,
        folder: String = "",
        noteName: String,
        body: String,
        tags: [String] = [],
        links: [String] = [],
        frontmatter: [String: String] = [:],
        date: Date = Date()
    ) {
        self.mode = mode
        self.folder = folder
        self.noteName = noteName
        self.body = body
        self.tags = tags
        self.links = links
        self.frontmatter = frontmatter
        self.date = date
    }

    public var fileName: String { "\(noteName).md" }

    /// Where the file sits relative to the vault root — what the preview shows.
    public var vaultPath: String {
        folder.isEmpty ? fileName : "\(folder)/\(fileName)"
    }

    /// The complete contents of a new note.
    public var renderedNote: String {
        var lines: [String] = ["---"]
        if !tags.isEmpty {
            lines.append("tags: [\(tags.joined(separator: ", "))]")
        }
        for key in frontmatter.keys.sorted() {
            lines.append("\(key): \(frontmatter[key] ?? "")")
        }
        lines.append("---")
        lines.append("")
        lines.append("# \(noteName)")
        lines.append("")
        lines.append(body)
        if !links.isEmpty {
            lines.append("")
            lines.append("## Related")
            lines.append("")
            lines.append(contentsOf: links.map { "- [[\($0)]]" })
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The single line added to an existing note. Bulleted and dated so a year
    /// of these still reads as a list rather than a wall of text.
    public var renderedAppendix: String {
        var line = "- \(singleLineBody)"
        if !links.isEmpty {
            line += " " + links.map { "[[\($0)]]" }.joined(separator: " ")
        }
        return line + " — *\(Self.dayStamp(date))*"
    }

    /// What the confirmation sheet renders, whichever mode this is.
    public var previewMarkdown: String {
        switch mode {
        case .createNote:
            return renderedNote
        case .appendToNote(let heading):
            return "## \(heading)\n\n\(renderedAppendix)\n"
        }
    }

    private var singleLineBody: String {
        body.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// `yyyy-MM-dd` without a `DateFormatter`, which is neither `Sendable` nor
    /// locale-stable — this needs to read the same in every vault.
    public static func dayStamp(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// Makes a transcript safe to use as a file name. Obsidian additionally
    /// treats `[ ] # ^ | ` as unsafe in links, so they go too.
    public static func sanitizedNoteName(_ raw: String, maxLength: Int = 80) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|[]#^")
            .union(.controlCharacters)
        let cleaned = raw.components(separatedBy: forbidden).joined(separator: " ")
        let collapsed = cleaned.split(whereSeparator: { $0 == " " || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let trimmed = String(collapsed.prefix(maxLength))
            .trimmingCharacters(in: .whitespaces)
        // A dot-leading name hides the file; an empty one can't be written.
        return trimmed.hasPrefix(".") || trimmed.isEmpty ? "Untitled" : trimmed
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
        case .markdownNote(let d):
            switch d.mode {
            case .createNote:            return "New note: \(d.noteName)"
            case .appendToNote:          return "Add to \(d.noteName)"
            }
        case .workoutLog(let d):
            return d.exercises.isEmpty
                ? "Log training session"
                : "Log training: \(d.exerciseNames)"
        case .mealLog(let d):
            return "Log meal: \(d.summary)"
        }
    }

    var systemImage: String {
        switch self {
        case .email:         return "envelope.fill"
        case .calendarEvent: return "calendar"
        case .reminder:      return "checklist"
        case .logEntry(let d): return d.kind.systemImage
        case .note:          return "note.text"
        case .markdownNote(let d):
            return d.mode.isAppend ? "text.append" : "doc.badge.plus"
        case .workoutLog:    return "figure.strengthtraining.traditional"
        case .mealLog:       return "fork.knife"
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
        case .markdownNote(let d):
            return d.mode.isAppend ? "Append" : "Create Note"
        case .workoutLog:    return "Log Session"
        case .mealLog:       return "Log Meal"
        }
    }
}
