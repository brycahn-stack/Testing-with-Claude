import SwiftUI
import VoiceJournalCore

@main
struct VoiceJournalApp: App {
    @StateObject private var store: JournalStore
    @StateObject private var pipeline: EntryPipeline
    @StateObject private var session: PhoneSessionManager

    init() {
        let store = JournalStore()
        let pipeline = EntryPipeline(store: store)
        _store = StateObject(wrappedValue: store)
        _pipeline = StateObject(wrappedValue: pipeline)
        _session = StateObject(wrappedValue: PhoneSessionManager(pipeline: pipeline))
    }

    var body: some Scene {
        WindowGroup {
            InboxView()
                .environmentObject(store)
                .environmentObject(pipeline)
                .task { _ = await SpeechTranscriber.requestAuthorization() }
        }
    }
}
