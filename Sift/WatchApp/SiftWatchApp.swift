import SwiftUI

@main
struct SiftWatchApp: App {
    // Activating the session as early as possible means queued transfers start
    // moving the moment the watch app launches.
    @StateObject private var session = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            RecordingView()
                .environmentObject(session)
        }
    }
}
