import SwiftUI
import SiftCore

/// Confirmation sheet for a training session.
///
/// Editable down to the individual set, because the extractor is rules and will
/// sometimes mishear — correcting "185" to "225" here is faster than fixing a
/// log later, and it's the difference between a training record you trust and
/// one you stop opening.
struct WorkoutLogPreview: View {
    @Binding var draft: WorkoutDraft

    var body: some View {
        Form {
            if draft.exercises.isEmpty {
                Section {
                    Label("No sets picked out of this one.", systemImage: "questionmark.circle")
                        .font(.subheadline)
                    Text("It'll be logged with the memo kept as-is. You can still add exercises below.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach($draft.exercises) { $exercise in
                Section {
                    ForEach($exercise.sets) { $set in
                        SetRow(set: $set)
                    }
                    .onDelete { offsets in
                        $exercise.wrappedValue.sets.remove(atOffsets: offsets)
                    }

                    Button {
                        // A new set almost always mirrors the last one.
                        $exercise.wrappedValue.sets.append(exercise.sets.last.map {
                            ExerciseSet(reps: $0.reps, weight: $0.weight, unit: $0.unit)
                        } ?? ExerciseSet())
                    } label: {
                        Label("Add set", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                } header: {
                    TextField("Exercise", text: $exercise.name)
                        .textInputAutocapitalization(.words)
                        .font(.subheadline.weight(.semibold))
                } footer: {
                    if exercise.sets.count > 1 {
                        Text(exercise.summary)
                    }
                }
            }
            .onDelete { draft.exercises.remove(atOffsets: $0) }

            Section {
                Button {
                    draft.exercises.append(LoggedExercise(name: "", sets: [ExerciseSet()]))
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
            }

            Section("What you said") {
                Text(draft.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label("Stays in Sift. Your watch already logged the calories and heart rate — Sift reads those rather than writing a second workout.",
                      systemImage: "applewatch")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// One set: weight, unit, reps. Blank weight means bodyweight.
private struct SetRow: View {
    @Binding var set: ExerciseSet

    var body: some View {
        HStack(spacing: 8) {
            NumberField(placeholder: "BW", value: $set.weight, width: 64)

            Picker("", selection: $set.unit) {
                ForEach(WeightUnit.allCases, id: \.self) { unit in
                    Text(unit.shortName).tag(unit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .disabled(set.weight == nil)

            Text("×").foregroundStyle(.secondary)

            NumberField(
                placeholder: "reps",
                value: Binding(
                    get: { set.reps.map(Double.init) },
                    set: { set.reps = $0.map { Int($0) } }
                ),
                width: 56
            )
            Text("reps").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

/// A numeric field that stays genuinely empty when there's no value — an
/// unstated weight is bodyweight, not zero.
private struct NumberField: View {
    let placeholder: String
    @Binding var value: Double?
    let width: CGFloat

    var body: some View {
        TextField(placeholder, text: Binding(
            get: { value.map { ExerciseSet.trimmed($0) } ?? "" },
            set: { text in
                let cleaned = text.trimmingCharacters(in: .whitespaces)
                value = cleaned.isEmpty ? nil : Double(cleaned)
            }
        ))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.trailing)
        .monospacedDigit()
        .frame(width: width)
        .textFieldStyle(.roundedBorder)
    }
}

// MARK: - Meals

/// Confirmation sheet for a meal.
///
/// Macro fields start blank unless the number was actually said. Filling them in
/// with a guess would be worse than leaving them empty — a made-up calorie count
/// is a number you'd go on to make decisions with.
struct MealLogPreview: View {
    @Binding var draft: MealDraft

    var body: some View {
        Form {
            Section("Meal") {
                TextField("What you ate", text: $draft.summary, axis: .vertical)
                    .lineLimit(1...3)
            }

            Section {
                MacroField(label: "Calories", unit: "kcal", value: $draft.nutrition.calories)
                MacroField(label: "Protein", unit: "g", value: $draft.nutrition.proteinGrams)
                MacroField(label: "Carbs", unit: "g", value: $draft.nutrition.carbGrams)
                MacroField(label: "Fat", unit: "g", value: $draft.nutrition.fatGrams)
            } header: {
                Text("Macros")
            } footer: {
                Text(draft.nutrition.isEmpty
                     ? "Nothing was stated, so nothing was recorded. Fill any of these in yourself, or leave them blank."
                     : "Only what you actually said. Sift doesn't estimate macros.")
            }

            Section("What you said") {
                Text(draft.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MacroField: View {
    let label: String
    let unit: String
    @Binding var value: Double?

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: Binding(
                get: { value.map { ExerciseSet.trimmed($0) } ?? "" },
                set: { text in
                    let cleaned = text.trimmingCharacters(in: .whitespaces)
                    value = cleaned.isEmpty ? nil : Double(cleaned)
                }
            ))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 70)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 30, alignment: .leading)
        }
    }
}
