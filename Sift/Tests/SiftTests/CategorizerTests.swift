import XCTest
@testable import SiftCore
@testable import Sift

final class CategorizerTests: XCTestCase {
    let categorizer = KeywordCategorizer()

    func testBusinessIdea() {
        let r = categorizer.categorize("I have a business idea for a SaaS product we could sell to founders")
        XCTAssertEqual(r.category, .businessIdea)
        XCTAssertGreaterThan(r.confidence, KeywordCategorizer.reviewThreshold)
    }

    func testTaskWithoutTimeIsTask() {
        let r = categorizer.categorize("Remind me to call the dentist")
        XCTAssertEqual(r.category, .task)
        XCTAssertTrue(r.detectedDates.isEmpty)
    }

    func testTaskWithTimeBecomesSchedule() {
        let r = categorizer.categorize("I need to meet Sarah tomorrow at 3pm")
        XCTAssertEqual(r.category, .schedule)
        XCTAssertFalse(r.detectedDates.isEmpty, "A concrete time should be detected")
    }

    func testWorkout() {
        let r = categorizer.categorize("Did five sets of squats and a two mile run at the gym")
        XCTAssertEqual(r.category, .workout)
    }

    func testMeal() {
        let r = categorizer.categorize("For lunch I ate a chicken salad, about forty grams of protein")
        XCTAssertEqual(r.category, .meal)
    }

    func testUnclassifiableBecomesLowConfidenceNote() {
        let r = categorizer.categorize("The sky looked really purple this evening")
        XCTAssertEqual(r.category, .note)
        XCTAssertLessThan(r.confidence, KeywordCategorizer.reviewThreshold)
    }

    func testDateDetection() {
        let dates = KeywordCategorizer.detectDates(in: "Let's meet next Monday at 10am")
        XCTAssertFalse(dates.isEmpty)
    }
}

final class RouterTests: XCTestCase {
    func testConfidentNoteProducesNoteProposal() async {
        let router = Router()
        let entry = JournalEntry(transcript: "some thought")
        let result = CategorizationResult(category: .note, confidence: 0.9)
        let proposed = await router.propose(entry, result)
        XCTAssertEqual(proposed.first?.destinationID, "note")
        XCTAssertEqual(proposed.first?.status, .pending, "Proposals start pending, never executed")
    }

    /// A destination that declines (e.g. a disconnected Google service) must
    /// yield to the next destination in line.
    func testDecliningDestinationFallsThrough() async {
        struct AlwaysDeclines: Destination {
            let id = "declines"
            let displayName = "Declines"
            func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool { true }
            func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? { nil }
            func execute(_ action: ProposedAction) async -> RoutingResult {
                .init(destinationID: id, destinationName: displayName, status: .failed, detail: "unreachable")
            }
        }
        let router = Router(destinations: [AlwaysDeclines(), NoteDestination()])
        let entry = JournalEntry(transcript: "some thought")
        let result = CategorizationResult(category: .note, confidence: 0.9)
        let proposed = await router.propose(entry, result)
        XCTAssertEqual(proposed.first?.destinationID, "note", "Declining should fall to the next destination")
    }

    func testLowConfidenceFailsTheBar() async {
        let router = Router()
        let entry = JournalEntry(transcript: "purple sky")
        let result = CategorizationResult(category: .note, confidence: 0.2)
        let proposed = await router.propose(entry, result)
        XCTAssertNotNil(proposed.first)
        XCTAssertFalse(router.meetsConfidenceBar(proposed[0]), "Low confidence must not clear the bar")
    }
}

final class TrustSettingsTests: XCTestCase {
    /// Sending mail must never auto-approve, no matter how confident or how
    /// permissive the user's setting is.
    @MainActor
    func testEmailSendNeverAutoApproves() {
        let trust = TrustSettings()
        trust.setLevel(.autoWhenConfident, for: "google.gmail")
        let action = ProposedAction(
            entryID: UUID(),
            destinationID: "google.gmail",
            destinationName: "Gmail",
            payload: .email(EmailDraft(to: ["a@b.com"], subject: "Hi", body: "Hi", sendImmediately: true)),
            confidence: 1.0
        )
        XCTAssertTrue(action.isHighStakes)
        XCTAssertFalse(trust.canAutoApprove(action))
    }

    @MainActor
    func testTrustedReminderAutoApprovesWhenConfident() {
        let trust = TrustSettings()
        trust.setLevel(.autoWhenConfident, for: "reminders")
        let action = ProposedAction(
            entryID: UUID(),
            destinationID: "reminders",
            destinationName: "Reminders",
            payload: .reminder(ReminderDraft(title: "Call the dentist")),
            confidence: 0.95
        )
        XCTAssertTrue(trust.canAutoApprove(action))
    }

    @MainActor
    func testAlwaysAskBlocksAutoApproval() {
        let trust = TrustSettings()
        trust.setLevel(.alwaysAsk, for: "reminders")
        let action = ProposedAction(
            entryID: UUID(),
            destinationID: "reminders",
            destinationName: "Reminders",
            payload: .reminder(ReminderDraft(title: "Call the dentist")),
            confidence: 0.99
        )
        XCTAssertFalse(trust.canAutoApprove(action))
    }
}

final class EmailDraftTests: XCTestCase {
    func testRecipientValidation() {
        XCTAssertFalse(EmailDraft(subject: "s", body: "b").hasValidRecipient)
        XCTAssertFalse(EmailDraft(to: ["Sarah"], subject: "s", body: "b").hasValidRecipient)
        XCTAssertTrue(EmailDraft(to: ["sarah@example.com"], subject: "s", body: "b").hasValidRecipient)
    }

    /// Sift extracts a *name* from speech and never invents an address — that's
    /// what makes the confirmation sheet load-bearing.
    func testRecipientHintIsANameNotAnAddress() {
        let hint = TitleBuilder.recipientHint(from: "Email Jordan about the pitch deck")
        XCTAssertEqual(hint, "Jordan")
        XCTAssertFalse(EmailDraft(subject: "s", body: "b", recipientHint: hint).hasValidRecipient)
    }
}
