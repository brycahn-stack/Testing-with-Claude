import XCTest
@testable import SiftCore
@testable import Sift

/// What the vault actually writes. The confirmation sheet renders these same
/// strings, so a break here is a break in what the user was shown.
final class MarkdownNoteDraftTests: XCTestCase {
    private func draft(
        mode: MarkdownNoteDraft.Mode = .createNote,
        body: String = "Body text.",
        links: [String] = []
    ) -> MarkdownNoteDraft {
        MarkdownNoteDraft(
            mode: mode,
            folder: "Sift",
            noteName: "Voice journal idea",
            body: body,
            tags: ["sift", "sift/idea"],
            links: links,
            frontmatter: ["source": "sift", "created": "2026-07-30"],
            date: Date(timeIntervalSince1970: 1_785_000_000)
        )
    }

    func testRenderedNoteHasFrontmatterTagsAndHeading() {
        let rendered = draft().renderedNote
        XCTAssertTrue(rendered.hasPrefix("---\ntags: [sift, sift/idea]\n"))
        // Sorted keys, so two runs of the same memo produce identical bytes.
        XCTAssertTrue(rendered.contains("created: 2026-07-30\nsource: sift\n---"))
        XCTAssertTrue(rendered.contains("# Voice journal idea"))
        XCTAssertTrue(rendered.hasSuffix("\n"))
    }

    func testRelatedSectionOnlyAppearsWithLinks() {
        XCTAssertFalse(draft().renderedNote.contains("## Related"))
        XCTAssertTrue(draft(links: ["About Me"]).renderedNote.contains("- [[About Me]]"))
    }

    func testVaultPathUsesFolder() {
        XCTAssertEqual(draft().vaultPath, "Sift/Voice journal idea.md")
        var rootLevel = draft()
        rootLevel.folder = ""
        XCTAssertEqual(rootLevel.vaultPath, "Voice journal idea.md")
    }

    func testAppendixIsOneDatedBullet() {
        let appended = draft(mode: .appendToNote(heading: "From Sift"),
                             body: "I work best\nin the mornings")
        // Multi-line speech collapses so the bullet stays a bullet.
        XCTAssertEqual(appended.renderedAppendix,
                       "- I work best in the mornings — *\(MarkdownNoteDraft.dayStamp(appended.date))*")
    }

    func testSanitizedNoteNameStripsPathAndLinkBreakers() {
        XCTAssertEqual(MarkdownNoteDraft.sanitizedNoteName("Q3/Q4 plan: [draft]"), "Q3 Q4 plan draft")
        // A leading dot would hide the file; an empty name can't be written.
        XCTAssertEqual(MarkdownNoteDraft.sanitizedNoteName(".hidden"), "Untitled")
        XCTAssertEqual(MarkdownNoteDraft.sanitizedNoteName("   "), "Untitled")
    }

    /// Creating a file is additive; editing one the user wrote is not.
    func testOnlyAppendsAreHighStakes() {
        func action(_ mode: MarkdownNoteDraft.Mode) -> ProposedAction {
            ProposedAction(entryID: UUID(), destinationID: "obsidian", destinationName: "Obsidian",
                           payload: .markdownNote(draft(mode: mode)), confidence: 1.0)
        }
        XCTAssertFalse(action(.createNote).isHighStakes)
        XCTAssertTrue(action(.appendToNote(heading: "From Sift")).isHighStakes)
    }

    @MainActor
    func testTrustSettingsCannotAutoApproveAnAppend() {
        let trust = TrustSettings()
        trust.setLevel(.autoWhenConfident, for: "obsidian.profile")
        let append = ProposedAction(
            entryID: UUID(), destinationID: "obsidian.profile", destinationName: "Obsidian · Profile",
            payload: .markdownNote(draft(mode: .appendToNote(heading: "From Sift"))),
            confidence: 1.0
        )
        XCTAssertFalse(trust.canAutoApprove(append),
                       "Editing a file the user wrote must always wait, whatever the trust level")
    }
}

/// The read-modify-write that touches an existing note. Pure and static, so it
/// can be exercised without a real vault on disk.
final class ObsidianAppendTests: XCTestCase {
    private let line = "- I prefer tea — *2026-07-30*"

    func testInsertsAtEndOfExistingSection() {
        let note = """
        # About Me

        I live in Denver.

        ## From Sift

        - I run in the mornings — *2026-01-01*

        ## Other

        stuff
        """
        let updated = ObsidianVault.inserting(line, under: "From Sift", into: note)
        let lines = updated.components(separatedBy: "\n")

        guard let existing = lines.firstIndex(of: "- I run in the mornings — *2026-01-01*"),
              let added = lines.firstIndex(of: line) else {
            return XCTFail("Both bullets should be present")
        }
        XCTAssertEqual(added, existing + 1, "New bullet joins the end of the list")
        // The rest of the user's note is untouched.
        XCTAssertEqual(lines.filter { $0 == "## Other" }.count, 1)
        XCTAssertTrue(updated.contains("I live in Denver."))
    }

    func testCreatesSectionWhenHeadingIsMissing() {
        let updated = ObsidianVault.inserting(line, under: "From Sift", into: "# About Me\n\nI live in Denver.\n")
        XCTAssertTrue(updated.hasSuffix("## From Sift\n\n\(line)\n"))
        XCTAssertTrue(updated.hasPrefix("# About Me"))
    }

    func testEmptySectionGetsABlankLineBeforeTheBullet() {
        let updated = ObsidianVault.inserting(line, under: "From Sift", into: "# A\n\n## From Sift\n")
        XCTAssertTrue(updated.contains("## From Sift\n\n\(line)"))
    }

    func testHeadingMatchIsCaseInsensitiveAndDoesNotDuplicate() {
        let updated = ObsidianVault.inserting(line, under: "From Sift", into: "## from sift\n\n- old\n")
        XCTAssertEqual(updated.components(separatedBy: "sift").count - 1, 1,
                       "Should reuse the existing heading rather than adding a second one")
    }

    func testCarriageReturnsAreNormalized() {
        let updated = ObsidianVault.inserting(line, under: "From Sift", into: "## From Sift\r\n\r\n- old\r\n")
        XCTAssertFalse(updated.contains("\r"))
        XCTAssertTrue(updated.contains("- old\n\(line)"))
    }
}

/// The narrow gate in front of the only feature that edits the user's own prose.
final class ObsidianProfileIntentTests: XCTestCase {
    func testRecognizesExplicitLeadIn() {
        XCTAssertEqual(ObsidianProfileIntent.fact(in: "Remember that I work best in the mornings"),
                       "I work best in the mornings")
        XCTAssertEqual(ObsidianProfileIntent.fact(in: "For the record, I value directness."),
                       "I value directness")
    }

    func testRecognizesStativeOpener() {
        XCTAssertEqual(ObsidianProfileIntent.fact(in: "I prefer dark roast coffee."),
                       "I prefer dark roast coffee")
    }

    /// The failure that would actually hurt: a to-do quietly rewritten into the
    /// user's profile note.
    func testRejectsTasksWearingALeadIn() {
        XCTAssertNil(ObsidianProfileIntent.fact(in: "Remember that I need to call the bank"))
        XCTAssertNil(ObsidianProfileIntent.fact(in: "Remember that I have to book flights"))
        XCTAssertNil(ObsidianProfileIntent.fact(in: "Note to self, I should email Dana"))
    }

    func testIgnoresOrdinaryMemos() {
        XCTAssertNil(ObsidianProfileIntent.fact(in: "Remind me to call the dentist"))
        XCTAssertNil(ObsidianProfileIntent.fact(in: "Had a great workout this morning"))
        XCTAssertNil(ObsidianProfileIntent.fact(in: ""))
    }
}

/// Links must point at pages that exist — an invented `[[link]]` creates an empty
/// note in the user's graph.
final class ObsidianLinkerTests: XCTestCase {
    func testLinksOnlyToKnownNotes() {
        let links = ObsidianLinker.links(in: "Some thoughts on product strategy for launch",
                                         knownNotes: ["Product Strategy", "Marketing Plan"])
        XCTAssertEqual(links.first, "Product Strategy")
        XCTAssertFalse(links.contains("Marketing Plan"))
    }

    func testPrefersTheLongestMatch() {
        let links = ObsidianLinker.links(in: "notes on product strategy",
                                         knownNotes: ["Product", "Product Strategy"])
        XCTAssertEqual(links.first, "Product Strategy")
    }

    func testRespectsWordBoundaries() {
        XCTAssertTrue(ObsidianLinker.links(in: "the catalog is long", knownNotes: ["Cats"]).isEmpty)
    }

    func testSkipsNamesCommonEnoughToMatchByAccident() {
        XCTAssertTrue(ObsidianLinker.links(in: "I have a few ideas", knownNotes: ["Ideas"]).isEmpty)
    }

    func testHonoursTheLimit() {
        let notes = ["Alpha One", "Beta Two", "Gamma Three", "Delta Four"]
        let links = ObsidianLinker.links(in: "alpha one beta two gamma three delta four",
                                         knownNotes: notes, limit: 2)
        XCTAssertEqual(links.count, 2)
    }
}

/// Routing behavior when no vault is connected — the common case, and the one
/// that must not break the existing flows.
final class ObsidianRoutingTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await ObsidianVault.shared.disconnect()
    }

    func testNoteFallsBackToTheJournalWhenNoVaultIsConnected() async {
        let router = Router()
        let entry = JournalEntry(transcript: "The sky looked purple this evening")
        let proposed = await router.propose(entry, CategorizationResult(category: .note, confidence: 0.9))
        XCTAssertEqual(proposed.first?.destinationID, "note",
                       "Obsidian should decline when disconnected so the note destination takes over")
    }

    func testIdeaFallsBackToTheIdeaLogWhenNoVaultIsConnected() async {
        let router = Router()
        let entry = JournalEntry(transcript: "Business idea: a voice journal that files itself")
        let proposed = await router.propose(entry, CategorizationResult(category: .businessIdea, confidence: 0.9))
        XCTAssertEqual(proposed.first?.destinationID, "log.idea")
    }

    /// A profile memo with no vault must not silently become a reminder to
    /// "prefer working in the mornings".
    func testProfileMemoDeclinesWithoutAVault() async {
        let router = Router()
        let entry = JournalEntry(transcript: "Remember that I work best in the mornings")
        let proposed = await router.propose(entry, CategorizationResult(category: .note, confidence: 0.9))
        XCTAssertNotEqual(proposed.first?.destinationID, "obsidian.profile")
    }
}
