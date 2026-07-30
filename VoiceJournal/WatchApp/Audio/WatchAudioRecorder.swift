import Foundation
import AVFoundation
import Combine

/// Records a short voice memo on the watch to a local `.m4a` file.
///
/// Kept minimal: one recording at a time, AAC-compressed so the file is small
/// enough to move over `WatchConnectivity` quickly.
@MainActor
final class WatchAudioRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let directory: URL

    override init() {
        let fm = FileManager.default
        let caches = (try? fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        directory = caches.appendingPathComponent("Recordings", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        super.init()
    }

    /// Requests mic access. Returns true if granted.
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Starts recording. Returns the destination file URL, or nil on failure.
    @discardableResult
    func start(entryID: UUID) -> URL? {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            return nil
        }

        let url = directory.appendingPathComponent("\(entryID.uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        guard let recorder = try? AVAudioRecorder(url: url, settings: settings) else { return nil }
        recorder.delegate = self
        guard recorder.record() else { return nil }

        self.recorder = recorder
        isRecording = true
        elapsed = 0
        startTimer()
        return url
    }

    /// Stops recording and returns the finished file URL and its duration.
    func stop() -> (url: URL, duration: TimeInterval)? {
        guard let recorder else { return nil }
        let url = recorder.url
        let duration = recorder.currentTime
        recorder.stop()
        stopTimer()
        isRecording = false
        self.recorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (url, duration)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                self.elapsed = recorder.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension WatchAudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.isRecording = false }
    }
}
