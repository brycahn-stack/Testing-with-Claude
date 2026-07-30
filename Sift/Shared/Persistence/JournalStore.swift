import Foundation
import Combine

/// The single source of truth for captured entries on whichever device it runs on.
///
/// Entries are persisted as JSON in the app's Application Support directory and
/// published so SwiftUI views stay in sync. Kept deliberately small — swapping in
/// SwiftData or Core Data later is a matter of reimplementing load/save.
@MainActor
public final class JournalStore: ObservableObject {
    @Published public private(set) var entries: [JournalEntry] = []

    private let fileURL: URL
    /// Directory where recorded audio is kept.
    public let audioDirectory: URL

    public init(filename: String = "journal.json") {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let root = support.appendingPathComponent("Sift", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)

        self.fileURL = root.appendingPathComponent(filename)
        self.audioDirectory = root.appendingPathComponent("Audio", isDirectory: true)
        try? fm.createDirectory(at: audioDirectory, withIntermediateDirectories: true)

        load()
    }

    // MARK: - Mutation

    public func add(_ entry: JournalEntry) {
        entries.insert(entry, at: 0) // newest first
        save()
    }

    public func update(_ entry: JournalEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else {
            add(entry)
            return
        }
        entries[idx] = entry
        save()
    }

    public func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        if let name = entry.audioFileName {
            try? FileManager.default.removeItem(at: audioDirectory.appendingPathComponent(name))
        }
        save()
    }

    public func entry(withID id: UUID) -> JournalEntry? {
        entries.first { $0.id == id }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        entries = (try? decoder.decode([JournalEntry].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
