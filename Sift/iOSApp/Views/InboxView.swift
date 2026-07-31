import SwiftUI
import SiftCore

/// The main phone screen: a reverse-chronological feed of everything you've said,
/// grouped so entries that need a human glance float to the top.
struct InboxView: View {
    @EnvironmentObject private var store: JournalStore
    @EnvironmentObject private var pipeline: EntryPipeline

    @State private var filter: JournalCategory?
    @State private var composing = false

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    emptyState
                } else {
                    List {
                        let review = filtered.filter(\.needsReview)
                        if !review.isEmpty {
                            Section("Needs Review") {
                                ForEach(review) { row(for: $0) }
                            }
                        }
                        Section(filter?.displayName ?? "All Entries") {
                            ForEach(filtered.filter { !$0.needsReview }) { row(for: $0) }
                                .onDelete(perform: delete)
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            .navigationDestination(for: UUID.self) { id in
                if let entry = store.entry(withID: id) {
                    EntryDetailView(entry: entry)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        composing = true
                    } label: {
                        Label("Type a memo", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $composing) {
                ComposeEntryView { text in
                    Task { await pipeline.ingestText(text) }
                }
            }
        }
    }

    private var filtered: [JournalEntry] {
        guard let filter else { return store.entries }
        return store.entries.filter { $0.category == filter }
    }

    private func row(for entry: JournalEntry) -> some View {
        NavigationLink(value: entry.id) {
            EntryRow(entry: entry)
        }
    }

    private var filterMenu: some View {
        Menu {
            Button("All") { filter = nil }
            Divider()
            ForEach(JournalCategory.allCases) { category in
                Button {
                    filter = category
                } label: {
                    Label(category.displayName, systemImage: category.systemImage)
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Entries Yet",
            systemImage: "mic.circle",
            description: Text("Tap the mic on your Apple Watch to capture a thought. It'll show up here, sorted automatically.")
        )
    }

    private func delete(at offsets: IndexSet) {
        let visible = filtered.filter { !$0.needsReview }
        offsets.map { visible[$0] }.forEach(store.delete)
    }
}

/// A single feed row.
/// Typing a memo instead of speaking it.
///
/// The watch is the primary way in, but not the only one it should be — you're
/// in a meeting, or the room is loud, or the transcript came out wrong and you'd
/// rather retype it than re-record. Text goes through the exact same pipeline as
/// speech: categorize, propose, route. Nothing about it is a shortcut.
///
/// It's also the only way to exercise the app on a simulator, which has no
/// paired watch to receive from.
struct ComposeEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    let onSubmit: (String) -> Void

    /// Shown under the field on an empty compose — the shapes Sift recognizes,
    /// which are otherwise invisible until you happen to say one.
    private let examples = [
        "Remind me to call the dentist",
        "Squats 5×5 at 225, felt heavy on the last rep",
        "Meeting with Sarah Thursday at 3",
        "Remember that I work best in the mornings"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's on your mind?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                }

                if text.isEmpty {
                    Section("Try one of these") {
                        ForEach(examples, id: \.self) { example in
                            Button {
                                text = example
                            } label: {
                                Text(example)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSubmit(text.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }
}

struct EntryRow: View {
    let entry: JournalEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.category.systemImage)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.summary)
                    .lineLimit(2)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(entry.category.displayName)
                    Text("·")
                    Text(entry.createdAt, format: .relative(presentation: .named))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
