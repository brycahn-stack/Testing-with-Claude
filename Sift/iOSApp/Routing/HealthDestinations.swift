import Foundation
import SiftCore

/// Files a training memo into Sift's own Health store, with sets and reps pulled
/// out of the speech.
///
/// **Why this doesn't write to Apple Health.** Two separate reasons, and both
/// matter:
///
/// 1. HealthKit has no data type for reps, sets, or weight lifted. It models
///    sessions and quantities — "45 minutes of strength training, 320 kcal" —
///    and there is no vocabulary for "squat, 5×3, 225 lb". Custom metadata is a
///    private blob the Health app won't show and no other app can read.
/// 2. The watch already recorded the session. Writing an `HKWorkout` from a
///    voice memo would duplicate it *and* credit fabricated calories to the
///    user's Activity rings — corrupting the number they care most about.
///
/// So Sift keeps what nothing else can hold, and `HealthKitService` reads the
/// watch's numbers back to sit alongside it.
struct WorkoutDestination: Destination {
    let id = "log.workout"
    let displayName = "Training Log"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .workout
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        let exercises = SetExtractor.extract(from: entry.transcript)

        return ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .workoutLog(WorkoutDraft(
                exercises: exercises,
                transcript: entry.transcript,
                date: entry.createdAt
            )),
            reasoning: Self.reasoning(for: exercises),
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        guard case .workoutLog(let draft) = action.payload else {
            return .init(destinationID: id, destinationName: displayName,
                         status: .failed, detail: "Wrong payload type")
        }

        let log = WorkoutLog(
            entryID: action.entryID,
            date: draft.date,
            exercises: draft.exercises,
            transcript: draft.transcript
        )
        await MainActor.run { HealthLogStore.shared.add(log) }

        // Ask HealthKit whether the watch recorded a session around the same
        // time. Best-effort: a session with no match is still a good session.
        Task { await HealthKitService.shared.attachMatchingWorkout(to: log) }

        let detail = draft.exercises.isEmpty
            ? "Logged session"
            : "\(draft.totalSets) sets — \(draft.exerciseNames)"
        return .init(destinationID: id, destinationName: displayName,
                     status: .success, detail: detail)
    }

    private static func reasoning(for exercises: [LoggedExercise]) -> String {
        guard !exercises.isEmpty else {
            return "Sounds like training. Couldn't pick out sets, so the memo is kept as-is."
        }
        let sets = exercises.reduce(0) { $0 + $1.sets.count }
        return "Heard \(sets) set\(sets == 1 ? "" : "s") across \(exercises.count) exercise\(exercises.count == 1 ? "" : "s")."
    }
}

/// Files a meal into the Health store.
///
/// Meals are the mirror image of training: HealthKit *does* have a home for them
/// (an `HKCorrelation` of type `.food` bundling calories and macros), but the
/// numbers are far harder to hear — "a chicken salad" carries no calorie count.
/// So Sift records what was actually said and leaves the rest blank rather than
/// inventing macros, and writing to HealthKit waits until extraction is good
/// enough to be worth trusting.
struct MealDestination: Destination {
    let id = "log.meal"
    let displayName = "Meal Log"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .meal
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        let nutrition = NutritionExtractor.extract(from: entry.transcript)

        return ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .mealLog(MealDraft(
                summary: TitleBuilder.cleanTitle(from: entry.transcript, maxWords: 12),
                transcript: entry.transcript,
                nutrition: nutrition,
                date: entry.createdAt
            )),
            reasoning: nutrition.isEmpty
                ? "Sounds like a meal. No macros mentioned, so none were recorded."
                : "Sounds like a meal, and some macros were stated outright.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        guard case .mealLog(let draft) = action.payload else {
            return .init(destinationID: id, destinationName: displayName,
                         status: .failed, detail: "Wrong payload type")
        }

        await MainActor.run {
            HealthLogStore.shared.add(MealLog(
                entryID: action.entryID,
                date: draft.date,
                summary: draft.summary,
                transcript: draft.transcript,
                nutrition: draft.nutrition
            ))
        }

        return .init(destinationID: id, destinationName: displayName,
                     status: .success, detail: "Logged \(draft.summary)")
    }
}
