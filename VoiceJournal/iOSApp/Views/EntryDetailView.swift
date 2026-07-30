import SwiftUI
import VoiceJournalCore

/// Detail screen for one entry: the transcript, where it was routed, and controls
/// to correct the category (which re-routes it).
struct EntryDetailView: View {
    @EnvironmentObject private var store: JournalStore
    @EnvironmentObject private var pipeline: EntryPipeline
    @Environment(\.dismiss) private var dismiss

    let entry: JournalEntry
    @State private var editedCategory: JournalCategory
    @State private var isReprocessing = false

    init(entry: JournalEntry) {
        self.entry = entry
        _editedCategory = State(initialValue: entry.category)
    }

    /// Always read the freshest copy from the store so re-routing updates live.
    private var current: JournalEntry { store.entry(withID: entry.id) ?? entry }

    var body: some View {
        Form {
            Section("Transcript") {
                Text(current.summary)
                    .textSelection(.enabled)
            }

            Section("Category") {
                Picker("Category", selection: $editedCategory) {
                    ForEach(JournalCategory.allCases) { category in
                        Label(category.displayName, systemImage: category.systemImage).tag(category)
                    }
                }
                HStack {
                    Text("Confidence")
                    Spacer()
                    Text("\(Int(current.confidence * 100))%")
                        .foregroundStyle(.secondary)
                }
                if editedCategory != current.category {
                    Button {
                        reroute()
                    } label: {
                        Label("Re-route as \(editedCategory.displayName)", systemImage: "arrow.triangle.branch")
                    }
                    .disabled(isReprocessing)
                }
            }

            if !current.detectedDates.isEmpty {
                Section("Detected Times") {
                    ForEach(current.detectedDates, id: \.self) { date in
                        Text(date, format: .dateTime.weekday().month().day().hour().minute())
                    }
                }
            }

            Section("Routed To") {
                if current.routingResults.isEmpty {
                    Text("Not routed").foregroundStyle(.secondary)
                } else {
                    ForEach(current.routingResults) { result in
                        RoutingResultRow(result: result)
                    }
                }
            }
        }
        .navigationTitle(current.category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    store.delete(current)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
    }

    private func reroute() {
        isReprocessing = true
        Task {
            await pipeline.reprocess(current, overrideCategory: editedCategory)
            isReprocessing = false
        }
    }
}

struct RoutingResultRow: View {
    let result: RoutingResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.destinationName).font(.subheadline).bold()
                Text(result.detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var icon: String {
        switch result.status {
        case .success:          return "checkmark.circle.fill"
        case .failed:           return "xmark.circle.fill"
        case .needsConfirmation: return "questionmark.circle.fill"
        }
    }

    private var color: Color {
        switch result.status {
        case .success:          return .green
        case .failed:           return .red
        case .needsConfirmation: return .orange
        }
    }
}
