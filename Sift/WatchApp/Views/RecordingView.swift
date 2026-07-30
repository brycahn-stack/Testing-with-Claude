import SwiftUI

/// The entire watch UI: one big mic button. Tap to start, tap to stop; the memo
/// is queued for the phone automatically. The goal is capture in under a second
/// so a fleeting thought never gets lost.
struct RecordingView: View {
    @EnvironmentObject private var session: WatchSessionManager
    @StateObject private var recorder = WatchAudioRecorder()

    @State private var currentEntryID: UUID?
    @State private var permissionDenied = false
    @State private var lastSentAt: Date?

    var body: some View {
        VStack(spacing: 8) {
            Button(action: toggle) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 96, height: 96)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .buttonStyle(.plain)
            .scaleEffect(recorder.isRecording ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)

            if recorder.isRecording {
                Text(timeString(recorder.elapsed))
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.red)
            } else {
                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .alert("Microphone Access Needed", isPresented: $permissionDenied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable microphone access in Settings to record journal entries.")
        }
    }

    private var statusText: String {
        if session.pendingTransfers > 0 {
            return "Syncing \(session.pendingTransfers)…"
        }
        if lastSentAt != nil {
            return "Saved · tap to add another"
        }
        return "Tap to journal"
    }

    private func toggle() {
        if recorder.isRecording {
            finishRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        Task {
            let granted = await recorder.requestPermission()
            guard granted else {
                permissionDenied = true
                return
            }
            let id = UUID()
            currentEntryID = id
            if recorder.start(entryID: id) == nil {
                permissionDenied = true
            }
        }
    }

    private func finishRecording() {
        guard let result = recorder.stop(), let id = currentEntryID else { return }
        // Ignore accidental sub-half-second taps.
        guard result.duration >= 0.5 else { return }
        session.send(
            entryID: id,
            fileURL: result.url,
            createdAt: Date(),
            duration: result.duration,
            watchTranscript: nil
        )
        lastSentAt = Date()
        currentEntryID = nil
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
