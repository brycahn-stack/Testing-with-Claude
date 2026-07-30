import SwiftUI
import SiftCore

/// The main phone screen: a reverse-chronological feed of everything you've said,
/// grouped so entries that need a human glance float to the top.
struct InboxView: View {
    @EnvironmentObject private var store: JournalStore

    @State private var filter: JournalCategory?

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
