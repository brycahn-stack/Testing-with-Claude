import Foundation
import WatchConnectivity
import VoiceJournalCore

/// Sends finished recordings from the watch to the iPhone.
///
/// Uses `transferFile` (rather than a live message) so the hand-off is queued and
/// guaranteed to be delivered by the system even if the phone is asleep or out of
/// range when you record. Metadata rides along in the transfer.
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published private(set) var reachable = false
    @Published private(set) var pendingTransfers = 0

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Queues a recorded memo for delivery to the phone.
    func send(entryID: UUID, fileURL: URL, createdAt: Date, duration: TimeInterval, watchTranscript: String?) {
        guard WCSession.isSupported() else { return }
        var metadata: [String: Any] = [
            WCKeys.messageType: WCKeys.typeNewEntry,
            WCKeys.entryID: entryID.uuidString,
            WCKeys.createdAt: createdAt.timeIntervalSince1970,
            WCKeys.duration: duration
        ]
        if let watchTranscript, !watchTranscript.isEmpty {
            metadata[WCKeys.watchTranscript] = watchTranscript
        }
        WCSession.default.transferFile(fileURL, metadata: metadata)
        DispatchQueue.main.async { self.pendingTransfers = WCSession.default.outstandingFileTransfers.count }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.reachable = session.isReachable }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async { self.pendingTransfers = session.outstandingFileTransfers.count }
    }
}
