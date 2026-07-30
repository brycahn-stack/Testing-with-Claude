import Foundation
import Speech

public enum TranscriptionError: Error {
    case notAuthorized
    case recognizerUnavailable
    case failed(String)
}

/// Anything that can turn a recorded audio file into text.
public protocol Transcriber: Sendable {
    func transcribe(fileURL: URL) async throws -> String
}

/// On-device transcription via Apple's `Speech` framework.
///
/// Requesting on-device recognition keeps voice memos private (nothing is sent to
/// Apple's servers when the language model is downloaded) and works offline.
public final class SpeechTranscriber: Transcriber {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Prompts for Speech permission if it hasn't been decided yet.
    public static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    public func transcribe(fileURL: URL) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !didResume else { return }
                    didResume = true
                    continuation.resume(throwing: TranscriptionError.failed(error.localizedDescription))
                    return
                }
                guard let result, result.isFinal else { return }
                guard !didResume else { return }
                didResume = true
                continuation.resume(returning: result.bestTranscription.formattedString)
            }
        }
    }
}
