import Foundation
import Combine

/// Training sessions and meals, persisted alongside the journal.
///
/// A singleton because destinations are `Sendable` value types with no way to be
/// handed a store — the same shape `GoogleAuthStore` and `ObsidianVault` use.
@MainActor
public final class HealthLogStore: ObservableObject {
    public static let shared = HealthLogStore()

    @Published public private(set) var workouts: [WorkoutLog] = []
    @Published public private(set) var meals: [MealLog] = []

    private let workoutsURL: URL
    private let mealsURL: URL

    public init(directoryName: String = "Sift") {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let root = support.appendingPathComponent(directoryName, isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        workoutsURL = root.appendingPathComponent("workouts.json")
        mealsURL = root.appendingPathComponent("meals.json")
        load()
    }

    // MARK: - Training

    public func add(_ workout: WorkoutLog) {
        workouts.insert(workout, at: 0) // newest first
        saveWorkouts()
    }

    public func update(_ workout: WorkoutLog) {
        guard let idx = workouts.firstIndex(where: { $0.id == workout.id }) else {
            add(workout)
            return
        }
        workouts[idx] = workout
        saveWorkouts()
    }

    public func delete(_ workout: WorkoutLog) {
        workouts.removeAll { $0.id == workout.id }
        saveWorkouts()
    }

    /// Attaches the watch's numbers to a session after a HealthKit lookup.
    public func attach(_ matched: MatchedWorkout, to workoutID: UUID) {
        guard let idx = workouts.firstIndex(where: { $0.id == workoutID }) else { return }
        workouts[idx].matchedWorkout = matched
        saveWorkouts()
    }

    // MARK: - Meals

    public func add(_ meal: MealLog) {
        meals.insert(meal, at: 0)
        saveMeals()
    }

    public func update(_ meal: MealLog) {
        guard let idx = meals.firstIndex(where: { $0.id == meal.id }) else {
            add(meal)
            return
        }
        meals[idx] = meal
        saveMeals()
    }

    public func delete(_ meal: MealLog) {
        meals.removeAll { $0.id == meal.id }
        saveMeals()
    }

    // MARK: - Derived

    /// Sessions grouped by day, newest day first — how the Health tab reads.
    public func workoutsByDay() -> [(day: Date, sessions: [WorkoutLog])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: workouts) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (day: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    public func mealsByDay() -> [(day: Date, meals: [MealLog])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: meals) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (day: $0.key, meals: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    /// Sessions in the last seven days.
    public func recentWorkouts(days: Int = 7, now: Date = Date()) -> [WorkoutLog] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return workouts
        }
        return workouts.filter { $0.date >= cutoff }
    }

    public func volumeKilograms(days: Int = 7, now: Date = Date()) -> Double {
        recentWorkouts(days: days, now: now).reduce(0) { $0 + $1.volumeKilograms }
    }

    // MARK: - Persistence

    private func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: workoutsURL) {
            workouts = (try? decoder.decode([WorkoutLog].self, from: data)) ?? []
        }
        if let data = try? Data(contentsOf: mealsURL) {
            meals = (try? decoder.decode([MealLog].self, from: data)) ?? []
        }
    }

    private func saveWorkouts() { write(workouts, to: workoutsURL) }
    private func saveMeals() { write(meals, to: mealsURL) }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
