import SwiftUI
import VoiceJournalCore

@main
struct VoiceJournalApp: App {
    @StateObject private var store: JournalStore
    @StateObject private var pipeline: EntryPipeline
    @StateObject private var session: PhoneSessionManager
    @StateObject private var google = GoogleConnectionsModel()

    init() {
        let store = JournalStore()
        let pipeline = EntryPipeline(store: store)
        _store = StateObject(wrappedValue: store)
        _pipeline = StateObject(wrappedValue: pipeline)
        _session = StateObject(wrappedValue: PhoneSessionManager(pipeline: pipeline))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                InboxView()
                    .tabItem { Label("Journal", systemImage: "mic.fill") }
                ConnectionsView()
                    .tabItem { Label("Connections", systemImage: "app.connected.to.app.below.fill") }
            }
            .environmentObject(store)
            .environmentObject(pipeline)
            .environmentObject(google)
            .task { _ = await SpeechTranscriber.requestAuthorization() }
        }
    }
}
