import Foundation
import SiftCore

/// Read/write access to an Obsidian vault the user picks from the Files app.
///
/// Obsidian has no server and no API — a vault is just a folder of Markdown on
/// disk. So unlike Gmail or Google Calendar there's no OAuth here: the user
/// grants access once by picking the folder, iOS hands back a **security-scoped
/// bookmark**, and that bookmark is the whole "connection". If the vault lives in
/// iCloud Drive (the common setup for Obsidian Sync users on a Mac), writes
/// propagate to the desktop on the next sync.
///
/// Two consequences worth knowing:
/// - Access is genuinely two-way. Sift can *read* existing notes, which is what
///   makes `[[wikilinks]]` resolve to real pages and lets it append a fact to a
///   note you already keep, like "About Me".
/// - Every touch goes through `NSFileCoordinator`, because a synced folder can be
///   written by the sync daemon at the same moment. Uncoordinated writes are how
///   you lose a paragraph.
actor ObsidianVault {
    static let shared = ObsidianVault()

    /// Cached note-name → file-URL map, so proposing doesn't re-walk the vault
    /// for every memo. Invalidated on write and on explicit refresh.
    private var cachedIndex: [String: URL]?

    // MARK: - Connecting

    /// Stores a bookmark for the folder the user picked. The URL arriving from
    /// `.fileImporter` is security-scoped and must be opened before it can be
    /// bookmarked.
    func connect(to url: URL) throws {
        let opened = url.startAccessingSecurityScopedResource()
        defer { if opened { url.stopAccessingSecurityScopedResource() } }

        // `.withSecurityScope` is a macOS-only creation option; on iOS a plain
        // bookmark of a picked URL resolves back into scope.
        let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        ObsidianDefaults.bookmark = bookmark
        ObsidianDefaults.vaultName = url.lastPathComponent
        cachedIndex = nil
    }

    func disconnect() {
        ObsidianDefaults.bookmark = nil
        ObsidianDefaults.vaultName = nil
        cachedIndex = nil
    }

    var isConnected: Bool { ObsidianDefaults.bookmark != nil }

    // MARK: - Reading

    /// Note names (without `.md`) found anywhere in the vault. Used to resolve
    /// `[[wikilinks]]` against pages that actually exist — Sift never invents a
    /// link to a note you don't have.
    func noteNames() throws -> [String] {
        try index().keys.sorted()
    }

    func noteExists(named name: String) -> Bool {
        (try? index())?[name.lowercased()] != nil
    }

    /// Full text of a note, by name. This is how the "About Me" append can show
    /// you the real file before changing it.
    func readNote(named name: String) throws -> String {
        guard let url = try index()[name.lowercased()] else {
            throw ObsidianVaultError.noteNotFound(name)
        }
        return try withVault { _ in try Self.coordinatedRead(url) }
    }

    /// The tail of a note, for the "here's where your line lands" preview.
    func tail(ofNote name: String, lines limit: Int = 12) -> String? {
        guard let text = try? readNote(named: name) else { return nil }
        let lines = Self.normalized(text).components(separatedBy: "\n")
        return lines.suffix(limit).joined(separator: "\n")
    }

    // MARK: - Writing

    /// Writes a new note. Never overwrites: a clashing name gets ` 2`, ` 3`, …
    /// appended, the same way a Finder copy would.
    @discardableResult
    func createNote(_ draft: MarkdownNoteDraft) throws -> String {
        try withVault { root in
            let folder = draft.folder.isEmpty ? root : root.appendingPathComponent(draft.folder, isDirectory: true)
            if !FileManager.default.fileExists(atPath: folder.path) {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            var candidate = folder.appendingPathComponent(draft.fileName)
            var suffix = 2
            while FileManager.default.fileExists(atPath: candidate.path) {
                candidate = folder.appendingPathComponent("\(draft.noteName) \(suffix).md")
                suffix += 1
            }

            try Self.coordinatedWrite(draft.renderedNote, to: candidate)
            cachedIndex = nil
            return draft.folder.isEmpty
                ? candidate.lastPathComponent
                : "\(draft.folder)/\(candidate.lastPathComponent)"
        }
    }

    /// Adds one line to an existing note under a heading, creating the heading at
    /// the end of the file if it isn't there. Read-modify-write inside a single
    /// coordinated block so a sync landing mid-edit can't drop the change.
    @discardableResult
    func appendToNote(_ draft: MarkdownNoteDraft) throws -> String {
        guard let heading = draft.mode.heading else {
            throw ObsidianVaultError.writeFailed("Append with no heading")
        }
        guard let url = try index()[draft.noteName.lowercased()] else {
            throw ObsidianVaultError.noteNotFound(draft.noteName)
        }

        return try withVault { root in
            let existing = try Self.coordinatedRead(url)
            let updated = Self.inserting(draft.renderedAppendix, under: heading, into: existing)
            try Self.coordinatedWrite(updated, to: url)
            cachedIndex = nil
            return Self.relativePath(of: url, in: root)
        }
    }

    // MARK: - Vault plumbing

    /// Resolves the bookmark and runs `body` with the security scope held open.
    /// Everything that touches the vault goes through here so the scope is never
    /// left dangling.
    private func withVault<T>(_ body: (URL) throws -> T) throws -> T {
        guard let bookmark = ObsidianDefaults.bookmark else {
            throw ObsidianVaultError.notConnected
        }

        var isStale = false
        let root: URL
        do {
            root = try URL(
                resolvingBookmarkData: bookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            throw ObsidianVaultError.bookmarkStale
        }

        guard root.startAccessingSecurityScopedResource() else {
            throw ObsidianVaultError.accessDenied
        }
        defer { root.stopAccessingSecurityScopedResource() }

        // The folder moved or was renamed; refresh the bookmark in place so the
        // user isn't asked to re-pick a vault that's still perfectly reachable.
        if isStale, let refreshed = try? root.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            ObsidianDefaults.bookmark = refreshed
        }

        return try body(root)
    }

    /// Lowercased note name → URL, walking the whole vault once.
    private func index() throws -> [String: URL] {
        if let cachedIndex { return cachedIndex }

        let built: [String: URL] = try withVault { root in
            var map: [String: URL] = [:]
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
            while let url = enumerator?.nextObject() as? URL {
                // `.obsidian` holds config and `.trash` holds deleted notes;
                // neither is a page anyone links to.
                if url.hasDirectoryPath {
                    if url.lastPathComponent == ".obsidian" || url.lastPathComponent == ".trash" {
                        enumerator?.skipDescendants()
                    }
                    continue
                }
                guard url.pathExtension.lowercased() == "md" else { continue }
                let name = url.deletingPathExtension().lastPathComponent
                // First match wins — Obsidian resolves ambiguous names the same way.
                if map[name.lowercased()] == nil { map[name.lowercased()] = url }
            }
            return map
        }

        cachedIndex = built
        return built
    }

    func refreshIndex() { cachedIndex = nil }

    // MARK: - File I/O

    private static func coordinatedRead(_ url: URL) throws -> String {
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(ObsidianVaultError.writeFailed("Read never ran"))

        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            result = Result { try String(contentsOf: readURL, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    private static func coordinatedWrite(_ text: String, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?

        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { writeURL in
            do {
                try text.write(to: writeURL, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
    }

    private static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    // MARK: - Markdown surgery

    /// Normalizes line endings so heading matching and joins behave the same on
    /// files written by any editor.
    static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Inserts `line` at the end of the `## heading` section, or appends the
    /// section to the file if it doesn't exist yet.
    ///
    /// Pure and static so the behavior is unit-testable without a real vault.
    static func inserting(_ line: String, under heading: String, into text: String) -> String {
        let target = "## \(heading)"
        var lines = normalized(text).components(separatedBy: "\n")

        guard let headingIndex = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(target) == .orderedSame
        }) else {
            var body = normalized(text)
            while body.hasSuffix("\n") { body.removeLast() }
            return body.isEmpty
                ? "\(target)\n\n\(line)\n"
                : "\(body)\n\n\(target)\n\n\(line)\n"
        }

        // The section runs until the next ATX heading of any level, or EOF.
        var end = headingIndex + 1
        while end < lines.count, !lines[end].hasPrefix("#") { end += 1 }

        // Back up over blank lines so the new bullet joins the existing list
        // rather than floating below it.
        var insertAt = end
        while insertAt > headingIndex + 1,
              lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }

        if insertAt == headingIndex + 1 {
            lines.insert(contentsOf: ["", line], at: insertAt)
        } else {
            lines.insert(line, at: insertAt)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

enum ObsidianVaultError: LocalizedError {
    case notConnected
    case bookmarkStale
    case accessDenied
    case noteNotFound(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No Obsidian vault is connected."
        case .bookmarkStale:
            return "Sift lost access to the vault folder. Reconnect it in Connections."
        case .accessDenied:
            return "iOS denied access to the vault folder. Reconnect it in Connections."
        case .noteNotFound(let name):
            return "Couldn't find a note called “\(name)” in the vault."
        case .writeFailed(let detail):
            return detail
        }
    }
}

// MARK: - Settings

/// What the user configures in Connections. Kept small and boring on purpose —
/// where new notes go, and which note holds facts about them.
struct ObsidianSettings: Codable, Equatable, Sendable {
    /// Vault-relative folder for new notes. Empty writes to the vault root.
    var folder: String = "Sift"
    /// The note that "remember that I…" facts get appended to.
    var profileNoteName: String = "About Me"
    /// The heading those facts land under, so Sift's additions stay in one place
    /// and are trivial to review or delete in bulk.
    var profileHeading: String = "From Sift"
    /// Whether to add `[[wikilinks]]` for vault notes mentioned in a memo.
    var linkToExistingNotes: Bool = true
    /// Whether "remember that I…" memos may append to the profile note at all.
    var profileCaptureEnabled: Bool = true
}

/// Bookmark + settings storage. Deliberately plain `UserDefaults` reads rather
/// than actor state, so SwiftUI can render connection status synchronously
/// without awaiting the vault actor.
enum ObsidianDefaults {
    private static let bookmarkKey = "sift.obsidian.bookmark"
    private static let vaultNameKey = "sift.obsidian.vaultName"
    private static let settingsKey = "sift.obsidian.settings"

    static var bookmark: Data? {
        get { UserDefaults.standard.data(forKey: bookmarkKey) }
        set { UserDefaults.standard.set(newValue, forKey: bookmarkKey) }
    }

    static var vaultName: String? {
        get { UserDefaults.standard.string(forKey: vaultNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: vaultNameKey) }
    }

    static var settings: ObsidianSettings {
        get {
            guard let data = UserDefaults.standard.data(forKey: settingsKey),
                  let decoded = try? JSONDecoder().decode(ObsidianSettings.self, from: data)
            else { return ObsidianSettings() }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    static var isConnected: Bool { bookmark != nil }
}
