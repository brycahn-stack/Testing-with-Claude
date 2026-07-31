import SwiftUI
import SiftCore

@main
struct SiftApp: App {
    @StateObject private var store: JournalStore
    @StateObject private var proposals: ProposalStore
    @StateObject private var trust: TrustSettings
    @StateObject private var pipeline: EntryPipeline
    @StateObject private var session: PhoneSessionManager
    @StateObject private var google = GoogleConnectionsModel()
    @StateObject private var obsidian = ObsidianConnection()
    @StateObject private var health = HealthLogStore.shared
    @StateObject private var accounts = AccountStore()

    /// First-launch welcome: shows the sign-in screen once, fully skippable.
    /// Never shown again either way — an optional identity shouldn't nag.
    @AppStorage("sift.hasSeenWelcome") private var hasSeenWelcome = false
    @State private var showingWelcome = false

    init() {
        let store = JournalStore()
        let proposals = ProposalStore()
        let trust = TrustSettings()
        let pipeline = EntryPipeline(store: store, proposals: proposals, trust: trust)
        _store = StateObject(wrappedValue: store)
        _proposals = StateObject(wrappedValue: proposals)
        _trust = StateObject(wrappedValue: trust)
        _pipeline = StateObject(wrappedValue: pipeline)
        _session = StateObject(wrappedValue: PhoneSessionManager(pipeline: pipeline))
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                InboxView()
                    .tabItem { Label("Journal", systemImage: "mic.fill") }

                HealthView()
                    .tabItem { Label("Health", systemImage: "heart.fill") }

                ReviewView()
                    .tabItem { Label("Review", systemImage: "checkmark.circle") }
                    .badge(proposals.pendingCount)

                AssistantView()
                    .tabItem { Label("Assistant", systemImage: "sparkles") }

                ConnectionsView()
                    .tabItem { Label("Connections", systemImage: "app.connected.to.app.below.fill") }
            }
            .environmentObject(store)
            .environmentObject(proposals)
            .environmentObject(trust)
            .environmentObject(pipeline)
            .environmentObject(google)
            .environmentObject(obsidian)
            .environmentObject(health)
            .environmentObject(accounts)
            .sheet(isPresented: $showingWelcome, onDismiss: { hasSeenWelcome = true }) {
                AccountView()
            }
            .task {
                if !hasSeenWelcome { showingWelcome = true }
                // Apple sign-ins can be revoked from Settings; don't show an
                // identity Apple no longer honors.
                await accounts.refreshAppleCredentialState()
                _ = await SpeechTranscriber.requestAuthorization()
                proposals.pruneResolved()
            }
        }
    }
}
