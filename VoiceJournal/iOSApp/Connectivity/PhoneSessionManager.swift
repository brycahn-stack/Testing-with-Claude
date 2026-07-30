import Foundation
import WatchConnectivity
import VoiceJournalCore

/// Receives recordings transferred from the watch and feeds them into the
/// `EntryPipeline`.
@MainActor
final class PhoneSessionManager: NSObject, ObservableObject {
    private let pipeline: EntryPipeline

    init(pipeline: EntryPipeline) {
        self.pipeline = pipeline
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
}

extension PhoneSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    // Required stubs on iOS — the session can deactivate when switching watches.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        guard metadata[WCKeys.messageType] as? String == WCKeys.typeNewEntry,
              let idString = metadata[WCKeys.entryID] as? String,
              let id = UUID(uuidString: idString) else { return }

        let createdAt: Date = (metadata[WCKeys.createdAt] as? TimeInterval).map(Date.init(timeIntervalSince1970:)) ?? Date()
        let watchTranscript = metadata[WCKeys.watchTranscript] as? String

        // The system deletes the transferred file once this delegate returns, so
        // copy it to a stable temp location before the async work begins.
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".m4a")
        try? FileManager.default.copyItem(at: file.fileURL, to: temp)

        Task { @MainActor in
            await pipeline.ingest(id: id, fileURL: temp, createdAt: createdAt, watchTranscript: watchTranscript)
            try? FileManager.default.removeItem(at: temp)
        }
    }
}
