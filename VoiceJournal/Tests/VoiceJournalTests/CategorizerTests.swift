import XCTest
@testable import VoiceJournalCore
@testable import VoiceJournal

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
    func testLowConfidenceIsHeldForReview() async {
        let router = Router()
        let entry = JournalEntry(transcript: "purple sky")
        let result = CategorizationResult(category: .note, confidence: 0.2)
        let routed = await router.route(entry, result)
        XCTAssertEqual(routed.first?.status, .needsConfirmation)
        XCTAssertEqual(routed.first?.destinationID, "review")
    }

    func testConfidentNoteIsKept() async {
        let router = Router()
        let entry = JournalEntry(transcript: "some thought")
        let result = CategorizationResult(category: .note, confidence: 0.9)
        let routed = await router.route(entry, result)
        XCTAssertEqual(routed.first?.destinationID, "note")
        XCTAssertEqual(routed.first?.status, .success)
    }
}
