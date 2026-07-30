import Foundation
import Combine
import SiftCore

/// UI-facing state for the Obsidian connection.
///
/// Thin by design: the bookmark and settings live in `ObsidianDefaults` (so the
/// destinations can read them without touching the main actor) and this class
/// just mirrors them for SwiftUI and owns the async calls into the vault actor.
@MainActor
final class ObsidianConnection: ObservableObject {
    @Published private(set) var isConnected: Bool
    @Published private(set) var vaultName: String?
    /// Number of Markdown notes found — doubles as proof that access really works.
    @Published private(set) var noteCount: Int?
    @Published private(set) var busy = false
    @Published var lastError: String?

    /// Written straight back to `ObsidianDefaults` so a change in Connections is
    /// live for the next memo without any explicit save step.
    @Published var settings: ObsidianSettings {
        didSet { ObsidianDefaults.settings = settings }
    }

    init() {
        isConnected = ObsidianDefaults.isConnected
        vaultName = ObsidianDefaults.vaultName
        settings = ObsidianDefaults.settings
    }

    /// Called with the folder URL from `.fileImporter`.
    func connect(to url: URL) {
        busy = true
        Task {
            do {
                try await ObsidianVault.shared.connect(to: url)
                isConnected = true
                vaultName = ObsidianDefaults.vaultName
                await loadNoteCount()
            } catch {
                lastError = error.localizedDescription
                isConnected = false
            }
            busy = false
        }
    }

    func handlePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            connect(to: url)
        case .failure(let error):
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        Task {
            await ObsidianVault.shared.disconnect()
            isConnected = false
            vaultName = nil
            noteCount = nil
        }
    }

    /// Re-walks the vault. Worth doing when the Connections tab appears, since
    /// notes added on the Mac won't be known until we look again.
    func refresh() {
        guard isConnected else { return }
        Task {
            await ObsidianVault.shared.refreshIndex()
            await loadNoteCount()
        }
    }

    private func loadNoteCount() async {
        do {
            noteCount = try await ObsidianVault.shared.noteNames().count
        } catch {
            noteCount = nil
            lastError = error.localizedDescription
        }
    }

    /// Shown under the tile so the permission is as legible as the Google ones.
    var capabilitySummary: String {
        "Can read and write Markdown files in the folder you picked. Nothing outside it."
    }
}
