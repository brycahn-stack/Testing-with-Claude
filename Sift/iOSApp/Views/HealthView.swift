import SwiftUI
import SiftCore

/// The Health tab: training and meals, kept apart from the life/business feed.
///
/// A separate tab because body data has a different shape from a journal — you
/// read it as trends and sessions, not as a chronological stream of thoughts.
struct HealthView: View {
    @EnvironmentObject private var health: HealthLogStore
    @State private var segment: Segment = .training

    /// One spacing ladder for the whole tab. Both segments draw from it, so a
    /// gap under "Last 7 days" matches the gap under a day heading instead of
    /// each row type inventing its own padding.
    enum Metrics {
        /// Between stacked lines inside a row (time badge → exercise list).
        static let lineGap: CGFloat = 8
        /// Between exercises within one session — tighter than `lineGap`, so a
        /// session reads as one block rather than a list of loose rows.
        static let exerciseGap: CGFloat = 5
        /// Vertical breathing room on a row, above the list's own insets.
        static let rowPadding: CGFloat = 5
    }

    /// Named `Segment` rather than `Section` so it can't shadow SwiftUI's.
    enum Segment: String, CaseIterable, Identifiable {
        case training = "Training"
        case meals = "Meals"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch segment {
                case .training: trainingList
                case .meals:    mealList
                }
            }
            .navigationTitle("Health")
            .safeAreaInset(edge: .top) {
                Picker("Section", selection: $segment) {
                    ForEach(Segment.allCases) { choice in
                        Text(choice.rawValue).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                // Symmetric: without the top inset the control sits flush
                // against the large title and reads as part of it.
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    // MARK: - Training

    @ViewBuilder
    private var trainingList: some View {
        if health.workouts.isEmpty {
            EmptyState(
                systemImage: "figure.strengthtraining.traditional",
                title: "No sessions yet",
                message: "Say something like “squats, 5×5 at 225” and it lands here with the sets pulled out."
            )
        } else {
            List {
                WeeklySummary(workouts: health.recentWorkouts())

                ForEach(health.workoutsByDay(), id: \.day) { group in
                    Section(group.day.formatted(date: .complete, time: .omitted)) {
                        ForEach(group.sessions) { session in
                            WorkoutRow(session: session)
                        }
                        .onDelete { offsets in
                            offsets.map { group.sessions[$0] }.forEach { health.delete($0) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Meals

    @ViewBuilder
    private var mealList: some View {
        if health.meals.isEmpty {
            EmptyState(
                systemImage: "fork.knife",
                title: "No meals yet",
                message: "Say what you ate and it lands here. Macros are recorded only when you state them."
            )
        } else {
            List {
                ForEach(health.mealsByDay(), id: \.day) { group in
                    Section(group.day.formatted(date: .complete, time: .omitted)) {
                        ForEach(group.meals) { meal in
                            MealRow(meal: meal)
                        }
                        .onDelete { offsets in
                            offsets.map { group.meals[$0] }.forEach { health.delete($0) }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Weekly summary

/// Volume is the one number that means something across sessions. Bodyweight
/// sets contribute nothing to it, because Sift doesn't know what you weigh and
/// won't guess.
private struct WeeklySummary: View {
    let workouts: [WorkoutLog]

    private var volumeKilograms: Double {
        workouts.reduce(0) { $0 + $1.volumeKilograms }
    }
    private var totalSets: Int {
        workouts.reduce(0) { $0 + $1.totalSets }
    }

    var body: some View {
        Section("Last 7 days") {
            HStack(spacing: 0) {
                Stat(value: "\(workouts.count)", label: "sessions")
                divider
                Stat(value: "\(totalSets)", label: "sets")
                divider
                Stat(value: volumeText, label: "volume")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HealthView.Metrics.rowPadding)
        }
    }

    /// Fixed height rather than a full-bleed `Divider()`, which would stretch to
    /// the row's full height and collide with the cell's own separators.
    private var divider: some View {
        Divider().frame(height: 28)
    }

    private var volumeText: String {
        let pounds = volumeKilograms / WeightUnit.pounds.kilogramsPerUnit
        guard pounds > 0 else { return "—" }
        if pounds >= 1000 {
            return String(format: "%.1fk", pounds / 1000)
        }
        return String(Int(pounds.rounded()))
    }

    private struct Stat: View {
        let value: String
        let label: String

        var body: some View {
            VStack(spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Rows

private struct WorkoutRow: View {
    let session: WorkoutLog

    var body: some View {
        VStack(alignment: .leading, spacing: HealthView.Metrics.lineGap) {
            HStack {
                Text(session.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let matched = session.matchedWorkout {
                    WatchBadge(matched: matched)
                }
            }

            if session.isUnstructured {
                // Nothing parsed — show the words rather than pretend otherwise.
                Text(session.transcript)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                // Exercises get their own tighter rhythm; inheriting the outer
                // gap made a five-exercise session sprawl.
                VStack(alignment: .leading, spacing: HealthView.Metrics.exerciseGap) {
                    ForEach(session.exercises) { exercise in
                        HStack(alignment: .firstTextBaseline) {
                            Text(exercise.name)
                                .font(.subheadline.weight(.semibold))
                            Spacer(minLength: 12)
                            Text(exercise.summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .padding(.vertical, HealthView.Metrics.rowPadding)
    }
}

/// The watch's own numbers for this session — read from HealthKit, never
/// written by Sift.
private struct WatchBadge: View {
    let matched: MatchedWorkout

    var body: some View {
        HStack(spacing: 8) {
            Label(matched.durationText, systemImage: "clock")
            if let energy = matched.activeEnergyKilocalories {
                Label("\(Int(energy)) kcal", systemImage: "flame")
            }
            if let heartRate = matched.averageHeartRate {
                Label("\(Int(heartRate))", systemImage: "heart")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
    }
}

private struct MealRow: View {
    let meal: MealLog

    var body: some View {
        VStack(alignment: .leading, spacing: HealthView.Metrics.exerciseGap) {
            HStack(alignment: .firstTextBaseline) {
                Text(meal.summary).font(.subheadline.weight(.semibold))
                Spacer(minLength: 10)
                Text(meal.date.formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            // No macros stated means no chips at all — a row of zeroes would
            // read as measured data that nobody measured.
            if !meal.nutrition.isEmpty {
                MacroLine(nutrition: meal.nutrition)
            }
        }
        .padding(.vertical, HealthView.Metrics.rowPadding)
    }
}

private struct MacroLine: View {
    let nutrition: Nutrition

    var body: some View {
        HStack(spacing: 10) {
            if let calories = nutrition.calories { chip("\(Int(calories)) kcal") }
            if let protein = nutrition.proteinGrams { chip("P \(Int(protein))g") }
            if let carbs = nutrition.carbGrams { chip("C \(Int(carbs))g") }
            if let fat = nutrition.fatGrams { chip("F \(Int(fat))g") }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.quaternary))
    }
}

private struct EmptyState: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        }
    }
}
