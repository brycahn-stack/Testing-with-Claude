import XCTest
@testable import SiftCore
@testable import Sift

/// The parser that makes the Health tab worth having. Every case here is real
/// gym phrasing — the value of a rules-based extractor is entirely in how much
/// of that it covers.
final class SetExtractorTests: XCTestCase {

    /// Compact assertion: "225lbx5, 225lbx5" is easier to read than nested
    /// XCTAssertEquals over optionals.
    private func describe(_ sets: [ExerciseSet]) -> String {
        sets.map { set in
            let weight = set.weight.map { "\(ExerciseSet.trimmed($0))\(set.unit.shortName)" } ?? "bw"
            return "\(weight)x\(set.reps.map(String.init) ?? "?")"
        }
        .joined(separator: ", ")
    }

    private func assertExtract(
        _ transcript: String,
        _ expected: [(name: String, sets: String)],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let result = SetExtractor.extract(from: transcript)
        XCTAssertEqual(result.count, expected.count,
                       "Exercise count for “\(transcript)”", file: file, line: line)
        for (actual, wanted) in zip(result, expected) {
            XCTAssertEqual(actual.name, wanted.name, "Name in “\(transcript)”", file: file, line: line)
            XCTAssertEqual(describe(actual.sets), wanted.sets, "Sets in “\(transcript)”", file: file, line: line)
        }
    }

    // MARK: The core shapes

    func testSetsByRepsAtWeight() {
        assertExtract("Squats 5x5 at 225", [("Squat", "225lbx5, 225lbx5, 225lbx5, 225lbx5, 225lbx5")])
    }

    func testWeightForReps() {
        assertExtract("squat 225 for 5", [("Squat", "225lbx5")])
    }

    func testSpokenSetsOfReps() {
        assertExtract("Bench three sets of eight at 185",
                      [("Bench Press", "185lbx8, 185lbx8, 185lbx8")])
    }

    func testRepListSharesOneWeight() {
        assertExtract("deadlift 8, 8, 6 at 185",
                      [("Deadlift", "185lbx8, 185lbx8, 185lbx6")])
    }

    func testRampingSetsKeepTheirOwnWeights() {
        assertExtract("Squats 225 for 5, 245 for 3, 265 for 1",
                      [("Squat", "225lbx5, 245lbx3, 265lbx1")])
    }

    // MARK: Ambiguity

    /// "5 x 5" is sets × reps; "225 x 5" is a weight for five reps. An empty
    /// barbell is 45 lb, so the threshold splits them cleanly.
    func testWeightThresholdDisambiguatesAxB() {
        assertExtract("225 x 5 on squats", [("Squat", "225lbx5")])
        assertExtract("pull ups 3 x 12", [("Pull Up", "bwx12, bwx12, bwx12")])
    }

    func testLoneNumberReadsAsRepsOrWeightByThreshold() {
        assertExtract("did 20 pushups", [("Push Up", "bwx20")])
        assertExtract("squat 225", [("Squat", "225lbx?")])
    }

    // MARK: Speech quirks

    func testSpokenHundreds() {
        assertExtract("squats five sets of five at two twenty five",
                      [("Squat", "225lbx5, 225lbx5, 225lbx5, 225lbx5, 225lbx5")])
        assertExtract("front squat 3x3 at one thirty five",
                      [("Front Squat", "135lbx3, 135lbx3, 135lbx3")])
    }

    /// The rule only fires on adjacent numbers with a round ten in the middle,
    /// which is what stops "3 sets of 8" collapsing into 38.
    func testSpokenHundredsDoesNotEatOrdinaryCounts() {
        XCTAssertEqual(SetExtractor.combineSpokenNumbers("3 sets of 8"), "3 sets of 8")
        XCTAssertEqual(SetExtractor.combineSpokenNumbers("2 20 5"), "225")
        XCTAssertEqual(SetExtractor.combineSpokenNumbers("20 5"), "25")
    }

    func testKilogramsAreRecognized() {
        assertExtract("squat 100 kilos for 5", [("Squat", "100kgx5")])
    }

    func testNumbersBeforeTheExerciseName() {
        assertExtract("did 5x5 squats at 225",
                      [("Squat", "225lbx5, 225lbx5, 225lbx5, 225lbx5, 225lbx5")])
    }

    // MARK: Weight recovery

    /// "bench 3x8 185" strands the weight after the sets pattern has run.
    func testStrandedWeightIsApplied() {
        assertExtract("bench 3x8 185", [("Bench Press", "185lbx8, 185lbx8, 185lbx8")])
    }

    /// …but a leftover number below the threshold is not a weight.
    func testStrandedNumberBelowThresholdIsIgnored() {
        assertExtract("bench 3x8 185, rested 2 minutes",
                      [("Bench Press", "185lbx8, 185lbx8, 185lbx8")])
    }

    // MARK: Multiple exercises

    func testMultipleExercisesKeepTheirOwnSets() {
        assertExtract("chest day: bench 4x8 at 185, incline bench 3x10 at 135, dips 3 sets of 12", [
            ("Bench Press", "185lbx8, 185lbx8, 185lbx8, 185lbx8"),
            ("Incline Bench Press", "135lbx10, 135lbx10, 135lbx10"),
            ("Dip", "bwx12, bwx12, bwx12")
        ])
    }

    /// The longest alias wins, so "incline bench" is never filed under "bench".
    func testLongerAliasWins() {
        let mentions = SetExtractor.exerciseMentions(in: SetExtractor.normalize("incline bench press"))
        XCTAssertEqual(mentions.map(\.name), ["Incline Bench Press"])
    }

    /// "…and 4 sets of dips" — the count belongs to the exercise that follows.
    func testDanglingSetCountGoesToTheNextExercise() {
        assertExtract("lat pulldown 3 sets of 12 at 120 and 4 sets of dips", [
            ("Lat Pulldown", "120lbx12, 120lbx12, 120lbx12"),
            ("Dip", "bwx?, bwx?, bwx?, bwx?")
        ])
    }

    // MARK: Failing safely

    /// The contract when the rules don't fire: nothing invented, nothing lost.
    /// The memo survives on `WorkoutLog.transcript`.
    func testUnparseableMemoYieldsNothing() {
        XCTAssertTrue(SetExtractor.extract(from: "just did legs, felt strong").isEmpty)
        XCTAssertTrue(SetExtractor.extract(from: "rest day today").isEmpty)
    }

    func testAbsurdSetCountsAreRejected() {
        // "100 x 3" is a weight, not a hundred sets — and nothing should ever
        // expand into an unbounded list of sets.
        let sets = SetExtractor.extract(from: "squat 100 x 3").first?.sets ?? []
        XCTAssertEqual(sets.count, 1)
    }
}

/// Volume and summary math, which is what the Health tab actually displays.
final class HealthLogTests: XCTestCase {
    func testUniformSetsCollapseInSummary() {
        let exercise = LoggedExercise(name: "Squat", sets: (0..<5).map { _ in
            ExerciseSet(reps: 5, weight: 225, unit: .pounds)
        })
        XCTAssertEqual(exercise.summary, "5 × 5 @ 225 lb")
    }

    func testMixedSetsListIndividually() {
        let exercise = LoggedExercise(name: "Squat", sets: [
            ExerciseSet(reps: 5, weight: 225, unit: .pounds),
            ExerciseSet(reps: 3, weight: 245, unit: .pounds)
        ])
        XCTAssertEqual(exercise.summary, "225 lb × 5, 245 lb × 3")
    }

    /// Bodyweight sets contribute nothing: Sift doesn't know what the user
    /// weighs and won't guess a number they'd then track over time.
    func testBodyweightSetsAddNoVolume() {
        let exercise = LoggedExercise(name: "Pull Up", sets: [ExerciseSet(reps: 12)])
        XCTAssertEqual(exercise.volumeKilograms, 0)
    }

    func testVolumeIsUnitConsistent() {
        let pounds = LoggedExercise(name: "Squat", sets: [ExerciseSet(reps: 1, weight: 100, unit: .pounds)])
        let kilos = LoggedExercise(name: "Squat", sets: [ExerciseSet(reps: 1, weight: 100, unit: .kilograms)])
        XCTAssertGreaterThan(kilos.volumeKilograms, pounds.volumeKilograms)
        XCTAssertEqual(pounds.volumeKilograms, 45.359237, accuracy: 0.0001)
    }

    func testUnstructuredSessionKeepsTheTranscript() {
        let log = WorkoutLog(entryID: UUID(), transcript: "felt strong today")
        XCTAssertTrue(log.isUnstructured)
        XCTAssertEqual(log.transcript, "felt strong today")
    }
}

/// Macros are only recorded when they were actually said.
final class NutritionExtractorTests: XCTestCase {
    func testExplicitMacrosAreRead() {
        let nutrition = NutritionExtractor.extract(from: "chicken salad, about forty grams of protein")
        XCTAssertEqual(nutrition.proteinGrams, 40)
        XCTAssertNil(nutrition.calories)
    }

    func testCaloriesAreRead() {
        XCTAssertEqual(NutritionExtractor.extract(from: "had a burrito, 850 calories").calories, 850)
    }

    /// The important one: a meal with no numbers gets no numbers. A guessed
    /// calorie count is a number you'd go on to make decisions with.
    func testNothingIsInvented() {
        XCTAssertTrue(NutritionExtractor.extract(from: "had a chicken salad for lunch").isEmpty)
    }
}

/// Routing for the health categories.
final class HealthRoutingTests: XCTestCase {
    func testWorkoutMemoProducesAStructuredProposal() async {
        let router = Router()
        let entry = JournalEntry(transcript: "Squats 5x5 at 225")
        let proposed = await router.propose(entry, CategorizationResult(category: .workout, confidence: 0.9))

        guard case .workoutLog(let draft)? = proposed.first?.payload else {
            return XCTFail("Expected a workoutLog payload")
        }
        XCTAssertEqual(proposed.first?.destinationID, "log.workout")
        XCTAssertEqual(draft.exercises.first?.name, "Squat")
        XCTAssertEqual(draft.totalSets, 5)
    }

    func testMealMemoProducesAMealProposal() async {
        let router = Router()
        let entry = JournalEntry(transcript: "Had a chicken salad for lunch")
        let proposed = await router.propose(entry, CategorizationResult(category: .meal, confidence: 0.9))

        guard case .mealLog(let draft)? = proposed.first?.payload else {
            return XCTFail("Expected a mealLog payload")
        }
        XCTAssertTrue(draft.nutrition.isEmpty)
    }

    /// Training and meal logs are private and reversible, so nothing about them
    /// should demand a confirmation tap.
    func testHealthLogsAreNotHighStakes() async {
        let router = Router()
        let entry = JournalEntry(transcript: "Squats 5x5 at 225")
        let proposed = await router.propose(entry, CategorizationResult(category: .workout, confidence: 0.9))
        XCTAssertEqual(proposed.first?.isHighStakes, false)
    }
}
