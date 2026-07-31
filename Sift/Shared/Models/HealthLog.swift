import Foundation

/// Training and meal records, kept in Sift's own store.
///
/// **Why these don't live in Apple Health:** HealthKit models *sessions and
/// quantities*. It can hold "45 minutes of strength training, 320 kcal" but has
/// no data type for reps, sets, or weight lifted — there is simply no vocabulary
/// for "barbell squat, 5×3, 225 lb". Custom metadata on a workout sample is a
/// private blob the Health app won't display and no other app can read.
///
/// So the split is deliberate:
/// - **The watch owns** duration, heart rate, and calories. Sift reads them and
///   never writes a duplicate workout.
/// - **Sift owns** the exercises, sets, reps, and weight, because nowhere else
///   can represent them.
/// - **Your voice owns** how it felt, which nothing captures today.

// MARK: - Training

public enum WeightUnit: String, Codable, Sendable, CaseIterable {
    case pounds
    case kilograms

    public var shortName: String {
        switch self {
        case .pounds:    return "lb"
        case .kilograms: return "kg"
        }
    }

    /// For volume math, which has to be unit-consistent to mean anything.
    public var kilogramsPerUnit: Double {
        switch self {
        case .pounds:    return 0.45359237
        case .kilograms: return 1
        }
    }
}

/// One performed set. `weight == nil` means bodyweight, or a set where no load
/// was stated — both are real and neither should be invented.
public struct ExerciseSet: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var reps: Int?
    public var weight: Double?
    public var unit: WeightUnit

    public init(id: UUID = UUID(), reps: Int? = nil, weight: Double? = nil, unit: WeightUnit = .pounds) {
        self.id = id
        self.reps = reps
        self.weight = weight
        self.unit = unit
    }

    public var isBodyweight: Bool { weight == nil }

    /// "225 × 5", "5 reps", "×5" — whatever was actually said.
    public var displayText: String {
        let repText = reps.map { "\($0)" }
        guard let weight else {
            return repText.map { "\($0) reps" } ?? "1 set"
        }
        let weightText = "\(Self.trimmed(weight)) \(unit.shortName)"
        return repText.map { "\(weightText) × \($0)" } ?? weightText
    }

    /// Load moved by this set, in kilograms. Bodyweight sets contribute nothing,
    /// since Sift doesn't know what the user weighs and won't guess.
    public var volumeKilograms: Double {
        guard let weight, let reps else { return 0 }
        return weight * unit.kilogramsPerUnit * Double(reps)
    }

    /// Drops a pointless ".0" so 225.0 reads as "225" but 62.5 survives.
    public static func trimmed(_ value: Double) -> String {
        value == value.rounded()
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

/// One movement and every set of it in a session.
public struct LoggedExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Canonical name from the vocabulary, e.g. "Bench Press".
    public var name: String
    public var sets: [ExerciseSet]

    public init(id: UUID = UUID(), name: String, sets: [ExerciseSet] = []) {
        self.id = id
        self.name = name
        self.sets = sets
    }

    public var volumeKilograms: Double {
        sets.reduce(0) { $0 + $1.volumeKilograms }
    }

    /// The heaviest set, which is usually the one a lifter actually cares about.
    public var topSet: ExerciseSet? {
        sets.filter { $0.weight != nil }.max { ($0.weight ?? 0) < ($1.weight ?? 0) }
    }

    /// Collapses uniform sets: "5 × 5 @ 225 lb" instead of listing five identical rows.
    public var summary: String {
        guard !sets.isEmpty else { return "No sets recorded" }
        let reps = Set(sets.map(\.reps))
        let weights = Set(sets.map(\.weight))

        if sets.count > 1, reps.count == 1, weights.count == 1,
           let repCount = sets[0].reps {
            let base = "\(sets.count) × \(repCount)"
            guard let weight = sets[0].weight else { return base }
            return "\(base) @ \(ExerciseSet.trimmed(weight)) \(sets[0].unit.shortName)"
        }
        return sets.map(\.displayText).joined(separator: ", ")
    }
}

/// A training session: what was lifted, the memo it came from, and — once
/// matched — the numbers the watch recorded for the same block of time.
public struct WorkoutLog: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// The journal entry this was extracted from.
    public var entryID: UUID
    public var date: Date
    public var exercises: [LoggedExercise]
    /// The full memo, always kept. If the extractor understood nothing, the
    /// words are still here rather than lost.
    public var transcript: String
    /// The watch's own numbers for this session, when one lined up.
    public var matchedWorkout: MatchedWorkout?

    public init(
        id: UUID = UUID(),
        entryID: UUID,
        date: Date = Date(),
        exercises: [LoggedExercise] = [],
        transcript: String = "",
        matchedWorkout: MatchedWorkout? = nil
    ) {
        self.id = id
        self.entryID = entryID
        self.date = date
        self.exercises = exercises
        self.transcript = transcript
        self.matchedWorkout = matchedWorkout
    }

    public var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    public var volumeKilograms: Double { exercises.reduce(0) { $0 + $1.volumeKilograms } }

    /// True when the extractor got nothing structured — the Health tab shows the
    /// raw memo instead of pretending to have parsed it.
    public var isUnstructured: Bool { exercises.isEmpty }
}

/// Read from HealthKit, never written by Sift. This is the watch's record of the
/// same session, attached so the Health tab can show effort next to output.
public struct MatchedWorkout: Codable, Hashable, Sendable {
    public var uuid: UUID
    /// Display name of the `HKWorkoutActivityType`, e.g. "Traditional Strength Training".
    public var activityName: String
    public var start: Date
    public var end: Date
    public var activeEnergyKilocalories: Double?
    public var averageHeartRate: Double?

    public init(uuid: UUID, activityName: String, start: Date, end: Date,
                activeEnergyKilocalories: Double? = nil, averageHeartRate: Double? = nil) {
        self.uuid = uuid
        self.activityName = activityName
        self.start = start
        self.end = end
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.averageHeartRate = averageHeartRate
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }

    public var durationText: String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60, remainder = minutes % 60
        if hours > 0 { return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}

// MARK: - Meals

/// Macros. Every field is optional because Sift will not invent a number it
/// didn't hear — an unstated calorie count stays unstated.
public struct Nutrition: Codable, Hashable, Sendable {
    public var calories: Double?
    public var proteinGrams: Double?
    public var carbGrams: Double?
    public var fatGrams: Double?

    public init(calories: Double? = nil, proteinGrams: Double? = nil,
                carbGrams: Double? = nil, fatGrams: Double? = nil) {
        self.calories = calories
        self.proteinGrams = proteinGrams
        self.carbGrams = carbGrams
        self.fatGrams = fatGrams
    }

    public var isEmpty: Bool {
        calories == nil && proteinGrams == nil && carbGrams == nil && fatGrams == nil
    }
}

public struct MealLog: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var entryID: UUID
    public var date: Date
    /// What was eaten, in the user's own words, tidied.
    public var summary: String
    public var transcript: String
    /// Sparse until richer extraction lands. Unlike training data, meals have a
    /// real home in HealthKit (an `HKCorrelation` of type `.food`), so these are
    /// what would eventually be written there.
    public var nutrition: Nutrition

    public init(id: UUID = UUID(), entryID: UUID, date: Date = Date(),
                summary: String, transcript: String = "", nutrition: Nutrition = Nutrition()) {
        self.id = id
        self.entryID = entryID
        self.date = date
        self.summary = summary
        self.transcript = transcript
        self.nutrition = nutrition
    }
}
