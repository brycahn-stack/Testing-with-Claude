import Foundation
import Combine

/// Holds the queue of proposed actions awaiting the user's decision.
///
/// Kept separate from `JournalStore` because its lifecycle is different: entries
/// are a permanent record, proposals are transient work items that get approved,
/// dismissed, and eventually cleared.
@MainActor
public final class ProposalStore: ObservableObject {
    @Published public private(set) var proposals: [ProposedAction] = []

    private let fileURL: URL

    public init(filename: String = "proposals.json") {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let root = support.appendingPathComponent("Sift", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        self.fileURL = root.appendingPathComponent(filename)
        load()
    }

    /// Everything still awaiting a decision, newest first — what the Review tab shows.
    public var pending: [ProposedAction] {
        proposals.filter { $0.status == .pending }.sorted { $0.createdAt > $1.createdAt }
    }

    /// Recently resolved, for the "Done" section.
    public var resolved: [ProposedAction] {
        proposals.filter { $0.status != .pending }.sorted { $0.createdAt > $1.createdAt }
    }

    public var pendingCount: Int { proposals.lazy.filter { $0.status == .pending }.count }

    public func add(_ action: ProposedAction) {
        proposals.append(action)
        save()
    }

    public func add(contentsOf actions: [ProposedAction]) {
        guard !actions.isEmpty else { return }
        proposals.append(contentsOf: actions)
        save()
    }

    public func update(_ action: ProposedAction) {
        guard let idx = proposals.firstIndex(where: { $0.id == action.id }) else { return }
        proposals[idx] = action
        save()
    }

    public func proposals(forEntry entryID: UUID) -> [ProposedAction] {
        proposals.filter { $0.entryID == entryID }
    }

    public func remove(_ action: ProposedAction) {
        proposals.removeAll { $0.id == action.id }
        save()
    }

    /// Drops resolved items older than a week so the history doesn't grow forever.
    public func pruneResolved(olderThan interval: TimeInterval = 7 * 24 * 3600) {
        let cutoff = Date().addingTimeInterval(-interval)
        let before = proposals.count
        proposals.removeAll { $0.status != .pending && $0.createdAt < cutoff }
        if proposals.count != before { save() }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        proposals = (try? decoder.decode([ProposedAction].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(proposals) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
