import Foundation
import HealthKit
import SiftCore

/// Reads the watch's record of a workout so it can sit beside Sift's own.
///
/// **Read-only, deliberately.** Sift asks HealthKit for share permission on
/// nothing at all. If it wrote an `HKWorkout` from a voice memo it would create
/// a duplicate of the session the watch already captured, and credit invented
/// calories to the Activity rings. The watch owns effort; Sift owns the barbell
/// numbers the watch can't see.
///
/// Everything degrades quietly: no entitlement, no permission, no paired watch,
/// or no matching session all end the same way — the training log stands on its
/// own without the watch's numbers attached.
actor HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private var didRequestAuthorization = false

    /// How far either side of a memo to look for the session it describes.
    /// Generous, because people talk about a lift on the walk out of the gym.
    static let matchWindow: TimeInterval = 4 * 60 * 60

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Types Sift reads. There is no write set — see the note above.
    private var readTypes: Set<HKObjectType> {
        [
            HKObjectType.workoutType(),
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
    }

    /// Safe to call repeatedly; the system only shows its sheet once per type.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            didRequestAuthorization = true
            return true
        } catch {
            return false
        }
    }

    /// Workouts that overlap a window around `date`, newest first.
    func workouts(near date: Date, window: TimeInterval = HealthKitService.matchWindow) async -> [HKWorkout] {
        guard isAvailable else { return [] }
        if !didRequestAuthorization { _ = await requestAuthorization() }

        let range = HKQuery.predicateForSamples(
            withStart: date.addingTimeInterval(-window),
            end: date.addingTimeInterval(window),
            options: []
        )
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(range)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return (try? await descriptor.result(for: store)) ?? []
    }

    /// Finds the watch's session for a Sift training log and attaches it.
    ///
    /// Picks the workout whose *end* is nearest the memo, on the theory that
    /// people record the memo just after racking the last set.
    func attachMatchingWorkout(to log: WorkoutLog) async {
        let candidates = await workouts(near: log.date)
        guard let best = candidates.min(by: {
            abs($0.endDate.timeIntervalSince(log.date)) < abs($1.endDate.timeIntervalSince(log.date))
        }) else { return }

        let matched = await summarize(best)
        await MainActor.run { HealthLogStore.shared.attach(matched, to: log.id) }
    }

    /// Pulls the numbers worth showing off a workout sample.
    private func summarize(_ workout: HKWorkout) async -> MatchedWorkout {
        // `totalEnergyBurned` is deprecated; statistics is the supported path.
        let energy = workout
            .statistics(for: HKQuantityType(.activeEnergyBurned))?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie())

        return MatchedWorkout(
            uuid: workout.uuid,
            activityName: Self.name(for: workout.workoutActivityType),
            start: workout.startDate,
            end: workout.endDate,
            activeEnergyKilocalories: energy,
            averageHeartRate: await averageHeartRate(during: workout)
        )
    }

    /// Heart rate isn't carried on the workout itself — it's a separate sample
    /// stream that has to be averaged over the session's window.
    private func averageHeartRate(during workout: HKWorkout) async -> Double? {
        let range = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: range),
            options: .discreteAverage
        )
        let statistics = try? await descriptor.result(for: store)
        return statistics?
            .averageQuantity()?
            .doubleValue(for: .count().unitDivided(by: .minute()))
    }

    /// Display names for the handful of activity types Sift is likely to meet.
    /// Anything else falls back to a readable default rather than a raw enum.
    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: return "Strength Training"
        case .functionalStrengthTraining:  return "Functional Strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .running:                     return "Run"
        case .walking:                     return "Walk"
        case .cycling:                     return "Cycle"
        case .swimming:                    return "Swim"
        case .rowing:                      return "Row"
        case .yoga:                        return "Yoga"
        case .coreTraining:                return "Core Training"
        case .elliptical:                  return "Elliptical"
        case .stairClimbing:               return "Stair Climbing"
        case .hiking:                      return "Hike"
        default:                           return "Workout"
        }
    }
}
