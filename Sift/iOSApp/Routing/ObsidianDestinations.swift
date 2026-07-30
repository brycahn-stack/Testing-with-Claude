import Foundation
import SiftCore

/// Writes notes and business ideas into an Obsidian vault as Markdown.
///
/// Sits ahead of `LogDestination.idea` and `NoteDestination` in the router and
/// declines when no vault is connected, so ideas land in the vault if you keep
/// one and in the in-app log if you don't — the same shadowing trick the Google
/// destinations use over their Apple equivalents.
struct ObsidianDestination: Destination {
    let id = "obsidian"
    let displayName = "Obsidian"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .note || result.category == .businessIdea
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        guard await ObsidianVault.shared.isConnected else { return nil }
        let settings = ObsidianDefaults.settings

        let draft = MarkdownNoteDraft(
            mode: .createNote,
            folder: settings.folder,
            noteName: MarkdownNoteDraft.sanitizedNoteName(
                TitleBuilder.cleanTitle(from: entry.transcript, maxWords: 10)
            ),
            body: entry.transcript,
            tags: Self.tags(for: result.category),
            links: await ObsidianLinker.links(in: entry.transcript, enabled: settings.linkToExistingNotes),
            frontmatter: [
                "created": MarkdownNoteDraft.dayStamp(entry.createdAt),
                "source": "sift",
                "category": result.category.displayName
            ],
            date: entry.createdAt
        )

        return ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .markdownNote(draft),
            reasoning: result.category == .businessIdea
                ? "An idea worth keeping — filing it in your vault."
                : "No clear action, so it becomes a note in your vault.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        await ObsidianWriter.write(action, destinationID: id, destinationName: displayName)
    }

    private static func tags(for category: JournalCategory) -> [String] {
        switch category {
        case .businessIdea: return ["sift", "sift/idea"]
        default:            return ["sift", "sift/note"]
        }
    }
}

/// Appends durable facts about the user — "remember that I work best in the
/// mornings" — to a note they already keep, like `About Me`.
///
/// This is the one destination that *edits an existing file the user wrote*, so
/// it's the most invasive thing Sift does. Guard rails, in order:
/// - The intent match is narrow and rejects anything that reads like a task.
/// - Additions are bulleted under one heading, so a year of them is still one
///   block you can review, move, or delete wholesale.
/// - `MarkdownNoteDraft` marks appends `isHighStakes`, so no trust setting can
///   auto-approve one. It always waits for you, with the file's tail shown.
struct ObsidianProfileDestination: Destination {
    let id = "obsidian.profile"
    let displayName = "Obsidian · Profile"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        ObsidianDefaults.settings.profileCaptureEnabled
            && ObsidianProfileIntent.fact(in: entry.transcript) != nil
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        guard await ObsidianVault.shared.isConnected else { return nil }
        guard let fact = ObsidianProfileIntent.fact(in: entry.transcript) else { return nil }

        let settings = ObsidianDefaults.settings
        let links = await ObsidianLinker.links(in: entry.transcript, enabled: settings.linkToExistingNotes)
        let exists = await ObsidianVault.shared.noteExists(named: settings.profileNoteName)

        // The append draft is built either way — when the profile note doesn't
        // exist yet we reuse its rendered bullet as the body of a new note, so
        // the line reads identically whichever path created it.
        let appendDraft = MarkdownNoteDraft(
            mode: .appendToNote(heading: settings.profileHeading),
            folder: settings.folder,
            noteName: settings.profileNoteName,
            body: fact,
            links: links,
            date: entry.createdAt
        )

        let draft = exists ? appendDraft : MarkdownNoteDraft(
            mode: .createNote,
            folder: settings.folder,
            noteName: MarkdownNoteDraft.sanitizedNoteName(settings.profileNoteName),
            // Links are already inside the rendered bullet; don't repeat them
            // in a Related section.
            body: "## \(settings.profileHeading)\n\n\(appendDraft.renderedAppendix)",
            tags: ["sift", "sift/profile"],
            frontmatter: [
                "created": MarkdownNoteDraft.dayStamp(entry.createdAt),
                "source": "sift"
            ],
            date: entry.createdAt
        )

        return ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .markdownNote(draft),
            reasoning: exists
                ? "Sounds like a fact about you — adding it to “\(settings.profileNoteName)”."
                : "Sounds like a fact about you, but there's no “\(settings.profileNoteName)” note yet — this creates one.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        await ObsidianWriter.write(action, destinationID: id, destinationName: displayName)
    }
}

// MARK: - Shared write path

/// Both Obsidian destinations commit the same way; only the proposal differs.
enum ObsidianWriter {
    static func write(_ action: ProposedAction, destinationID: String, destinationName: String) async -> RoutingResult {
        guard case .markdownNote(let draft) = action.payload else {
            return .init(destinationID: destinationID, destinationName: destinationName,
                         status: .failed, detail: "Wrong payload type")
        }
        do {
            switch draft.mode {
            case .createNote:
                let path = try await ObsidianVault.shared.createNote(draft)
                return .init(destinationID: destinationID, destinationName: destinationName,
                             status: .success, detail: "Wrote \(path)", externalID: path)
            case .appendToNote(let heading):
                let path = try await ObsidianVault.shared.appendToNote(draft)
                return .init(destinationID: destinationID, destinationName: destinationName,
                             status: .success, detail: "Added under “\(heading)” in \(path)",
                             externalID: path)
            }
        } catch {
            return .init(destinationID: destinationID, destinationName: destinationName,
                         status: .failed, detail: error.localizedDescription)
        }
    }
}

// MARK: - Profile intent

/// Recognizes memos that state a durable fact about the speaker, as opposed to
/// something they need to *do*.
///
/// Deliberately conservative: it takes an explicit lead-in ("remember that I…")
/// or an unmistakably stative opener ("I prefer…"), and then rejects the result
/// if it reads like a task. Missing a fact costs nothing — it becomes an
/// ordinary note. Mistaking "remember that I need to call the bank" for a fact
/// would quietly corrupt the user's own writing, so the bar sits high.
enum ObsidianProfileIntent {
    /// Lead-ins that consume the subject, so the fact is rebuilt as "I …".
    private static let leadIns = [
        "remember that i ", "remember i ",
        "for the record i ", "for the record, i ",
        "note to self i ", "note to self, i ",
        "add to my about me that i ", "add to my about me, i ",
        "for my about me i ", "for my about me, i ",
        "add to my profile that i ", "add to my profile, i ",
        "about me i ", "about me, i "
    ]

    /// Sentences that are already a self-description.
    private static let stativeOpeners = [
        "i prefer ", "i tend to ", "i usually ", "i always ", "i never ",
        "i work best ", "i'm best ", "i am best ",
        "i'm the kind of ", "i am the kind of ",
        "i care about ", "i value ", "i believe "
    ]

    /// If the fact starts like one of these it's an action, not an attribute.
    private static let actionOpeners = [
        "need to", "needed to", "have to", "had to", "should", "must",
        "want to", "gotta", "got to", "ought to", "will ", "am going to",
        "'m going to", "have got to"
    ]

    static func fact(in transcript: String) -> String? {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        for lead in leadIns where lower.hasPrefix(lead) {
            return validated("I " + String(trimmed.dropFirst(lead.count)))
        }
        for opener in stativeOpeners where lower.hasPrefix(opener) {
            return validated(trimmed)
        }
        return nil
    }

    /// Tidies the sentence and vetoes anything action-shaped.
    private static func validated(_ raw: String) -> String? {
        var fact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = fact.last, last == "." || last == "," || last == ";" {
            fact.removeLast()
        }
        guard fact.count > 3 else { return nil }

        let lower = fact.lowercased()
        guard !lower.contains("remind me") else { return nil }
        // Everything after the leading "i ".
        let predicate = lower.hasPrefix("i ") ? String(lower.dropFirst(2)) : lower
        guard !actionOpeners.contains(where: { predicate.hasPrefix($0) }) else { return nil }

        return fact.prefix(1).uppercased() + fact.dropFirst()
    }
}

// MARK: - Wikilinks

/// Resolves `[[wikilinks]]` against notes that actually exist in the vault.
///
/// The rule that matters: Sift only links to pages it has *seen*. A link to a
/// note you don't have creates an empty page in your graph, which is exactly the
/// kind of quiet mess that makes people stop trusting an integration.
enum ObsidianLinker {
    /// Note names common enough to match by accident.
    private static let stopNotes: Set<String> = [
        "note", "notes", "todo", "todos", "task", "tasks", "idea", "ideas",
        "index", "home", "inbox", "daily", "readme", "untitled", "work",
        "life", "log", "logs", "journal", "today", "week", "month", "people"
    ]

    static func links(in transcript: String, enabled: Bool, limit: Int = 3) async -> [String] {
        guard enabled else { return [] }
        guard let names = try? await ObsidianVault.shared.noteNames() else { return [] }
        return links(in: transcript, knownNotes: names, limit: limit)
    }

    /// Pure form, so the matching rules are testable without a vault.
    static func links(in transcript: String, knownNotes: [String], limit: Int = 3) -> [String] {
        let haystack = " " + words(of: transcript).joined(separator: " ") + " "
        var found: [String] = []

        // Longest first, so "Product Strategy" wins over "Product".
        for note in knownNotes.sorted(by: { $0.count > $1.count }) {
            let needle = words(of: note).joined(separator: " ")
            guard needle.count >= 4, !stopNotes.contains(needle) else { continue }
            guard haystack.contains(" \(needle) ") else { continue }
            found.append(note)
            if found.count == limit { break }
        }
        return found
    }

    /// Lowercased word tokens, so matching respects word boundaries — "cat"
    /// must not match inside "catalog".
    private static func words(of text: String) -> [String] {
        let keep = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'-"))
        return text.lowercased()
            .components(separatedBy: keep.inverted)
            .filter { !$0.isEmpty }
    }
}
