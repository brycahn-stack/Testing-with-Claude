import Foundation
import SiftCore

/// Appends facts about *other people* to the per-person notes many vaults keep —
/// "Sarah mentioned she's moving to Austin in the spring" lands as a dated
/// bullet in `People/Sarah.md`.
///
/// This is the profile destination's machinery pointed at a different file: the
/// same single-heading rule, the same dated bullets, the same `isHighStakes`
/// append that no trust setting can auto-approve. What's new is only the intent
/// matcher, which has a harder job — third-person speech is looser than
/// "remember that I…", so the patterns demand both a *telling* verb (mentioned,
/// said, told me) and a capitalized name, and reject pronouns outright.
///
/// If the person's note already exists anywhere in the vault, the fact is
/// appended there — Sift never creates `People/Sarah.md` when the user already
/// keeps `Friends/Sarah.md`. Only when no note exists does it propose creating
/// one, in the configurable People folder.
struct ObsidianPersonDestination: Destination {
    let id = "obsidian.person"
    let displayName = "Obsidian · People"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        // Note-category only: "Sarah said the meeting moved to Thursday at 3"
        // classifies as schedule and should become a calendar proposal, not a
        // line in Sarah's note.
        result.category == .note
            && ObsidianDefaults.settings.peopleCaptureEnabled
            && ObsidianPersonIntent.match(in: entry.transcript) != nil
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        guard await ObsidianVault.shared.isConnected else { return nil }
        guard let match = ObsidianPersonIntent.match(in: entry.transcript) else { return nil }

        let settings = ObsidianDefaults.settings
        let noteName = MarkdownNoteDraft.sanitizedNoteName(match.name)
        let exists = await ObsidianVault.shared.noteExists(named: noteName)

        // Never link a note to itself — the fact lives *in* the person's note.
        let links = await ObsidianLinker.links(in: entry.transcript, enabled: settings.linkToExistingNotes)
            .filter { $0.lowercased() != noteName.lowercased() }

        let appendDraft = MarkdownNoteDraft(
            mode: .appendToNote(heading: settings.profileHeading),
            folder: settings.peopleFolder,
            noteName: noteName,
            body: match.fact,
            links: links,
            date: entry.createdAt
        )

        let draft = exists ? appendDraft : MarkdownNoteDraft(
            mode: .createNote,
            folder: settings.peopleFolder,
            noteName: noteName,
            body: "## \(settings.profileHeading)\n\n\(appendDraft.renderedAppendix)",
            tags: ["sift", "sift/person"],
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
                ? "Sounds like something worth keeping about \(match.name) — adding it to their note."
                : "Sounds like something worth keeping about \(match.name), but there's no note for them yet — this creates one in \(settings.peopleFolder.isEmpty ? "the vault" : settings.peopleFolder).",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        await ObsidianWriter.write(action, destinationID: id, destinationName: displayName)
    }
}

/// Recognizes memos that report something about a named person.
///
/// The bar sits high for the same reason the profile matcher's does: a missed
/// match costs nothing (the memo becomes an ordinary note), while a false one
/// writes into a page the user curates about someone they know. So the patterns
/// require a telling verb *and* a capitalized single-word name, and pronouns or
/// sentence-starting words that merely look like names are rejected.
///
/// Matching runs on the raw transcript, not a lowercased copy — capitalization
/// is the signal that separates "Sarah mentioned" from "she mentioned", and
/// speech transcription capitalizes recognized names.
enum ObsidianPersonIntent {
    struct Match: Equatable {
        /// The person, as heard — becomes the note name.
        let name: String
        /// The fact, rewritten to read naturally inside that person's note.
        let fact: String
    }

    /// Capitalized tokens that start sentences without being names.
    private static let notNames: Set<String> = [
        "He", "She", "They", "We", "You", "It", "Someone", "Somebody",
        "Everyone", "Everybody", "Nobody", "My", "The", "That", "This",
        "These", "Those", "Also", "And", "But", "So", "Then", "Just",
        "Today", "Yesterday", "Tomorrow", "Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday", "Sunday"
    ]

    /// "Sarah mentioned (that) she's moving" → name "Sarah",
    /// fact "Mentioned that she's moving".
    private static let toldPattern = try? NSRegularExpression(
        pattern: #"^\s*([A-Z][a-z]+)\s+(mentioned|said|told me)\s+(?:that\s+)?(.+)$"#,
        options: [.dotMatchesLineSeparators]
    )

    /// "talked to Sarah about the roadmap" → "Talked about the roadmap".
    /// "met with Sarah about the lease" → "Met about the lease".
    ///
    /// Verbs match either case explicitly rather than via `.caseInsensitive`,
    /// which would also relax the `[A-Z]` name capital — the one signal
    /// separating "Sarah" from "she".
    private static let talkedPattern = try? NSRegularExpression(
        pattern: #"(?:^|\.\s+)(?:[Ii]\s+)?([Tt]alked to|[Tt]alked with|[Cc]aught up with|[Mm]et with)\s+([A-Z][a-z]+)\s+about\s+(.+)$"#,
        options: [.dotMatchesLineSeparators]
    )

    static func match(in transcript: String) -> Match? {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        if let regex = toldPattern,
           let result = regex.firstMatch(in: text, range: range),
           let name = capture(1, of: result, in: text),
           let verb = capture(2, of: result, in: text),
           let rest = capture(3, of: result, in: text),
           isName(name) {
            // "told me" reads as "Told me X" inside the note; "mentioned"/"said"
            // read as "Mentioned that X".
            let fact = verb == "told me" ? "Told me \(rest)" : "\(verb.capitalized) that \(rest)"
            return validated(name: name, fact: fact)
        }

        if let regex = talkedPattern,
           let result = regex.firstMatch(in: text, range: range),
           let verb = capture(1, of: result, in: text),
           let name = capture(2, of: result, in: text),
           let topic = capture(3, of: result, in: text),
           isName(name) {
            let opener = verb.lowercased().hasPrefix("met") ? "Met about" : "Talked about"
            return validated(name: name, fact: "\(opener) \(topic)")
        }

        return nil
    }

    private static func isName(_ token: String) -> Bool {
        token.count >= 2 && !notNames.contains(token)
    }

    /// Same vetoes as the profile matcher: too short, or actually a task.
    private static func validated(name: String, fact: String) -> Match? {
        var fact = fact.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = fact.last, last == "." || last == "," || last == ";" {
            fact.removeLast()
        }
        guard fact.count > 8 else { return nil }
        guard !fact.lowercased().contains("remind me") else { return nil }
        return Match(name: name, fact: fact)
    }

    private static func capture(_ index: Int, of result: NSTextCheckingResult, in text: String) -> String? {
        guard index < result.numberOfRanges,
              let range = Range(result.range(at: index), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespaces)
    }
}
