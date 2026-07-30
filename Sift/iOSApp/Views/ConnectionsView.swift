import SwiftUI
import SiftCore

/// The Connections tab: every service the app can hand memos to, with individual
/// connect/disconnect controls. System integrations (Reminders, Calendar) are
/// listed for transparency; Google services carry real OAuth state.
struct ConnectionsView: View {
    @EnvironmentObject private var google: GoogleConnectionsModel
    @EnvironmentObject private var trust: TrustSettings

    /// Destinations the user can set a trust level for, in display order.
    private let trustable: [(id: String, name: String)] = [
        ("google.gmail", "Gmail"),
        ("google.calendar", "Google Calendar"),
        ("calendar", "Calendar"),
        ("reminders", "Reminders"),
        ("log.workout", "Workout Log"),
        ("log.meal", "Meal Log"),
        ("log.idea", "Idea Inbox")
    ]

    var body: some View {
        NavigationStack {
            List {
                if !GoogleOAuthConfig.isConfigured {
                    Section {
                        Label {
                            Text("Google setup needed: create an iOS OAuth client in Google Cloud Console and paste its ID into GoogleService.swift. Until then, Connect is disabled.")
                                .font(.footnote)
                        } icon: {
                            Image(systemName: "wrench.and.screwdriver")
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Google") {
                    ForEach(GoogleService.allCases) { service in
                        GoogleConnectionRow(service: service)
                    }
                }

                Section("Built-in (Apple)") {
                    builtInRow(name: "Reminders", detail: "Tasks without a time", systemImage: "checklist", color: .orange)
                    builtInRow(name: "Calendar", detail: "Scheduling memos (fallback when Google Calendar is off)", systemImage: "calendar", color: .red)
                }

                Section {
                    ForEach(trustable, id: \.id) { destination in
                        Picker(destination.name, selection: Binding(
                            get: { trust.level(for: destination.id) },
                            set: { trust.setLevel($0, for: destination.id) }
                        )) {
                            ForEach(TrustLevel.allCases, id: \.self) { level in
                                Text(level.displayName).tag(level)
                            }
                        }
                    }
                } header: {
                    Text("When to ask")
                } footer: {
                    Text("“Auto when confident” lets Sift act without waiting, above \(Int(TrustSettings.autoApproveThreshold * 100))% confidence. Sending email and inviting people always waits for you, whatever this is set to.")
                }

                Section {
                    Text("Connections are granted individually with the narrowest scopes possible: Gmail can send mail and save drafts but cannot read your inbox, and Google Calendar can only manage events. Tokens are stored in the iOS Keychain. Disconnect any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connections")
            .alert("Connection Error", isPresented: .init(
                get: { google.lastError != nil },
                set: { if !$0 { google.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(google.lastError ?? "")
            }
        }
    }

    private func builtInRow(name: String, detail: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            ServiceIcon(systemImage: systemImage, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Built in")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// One Google service row: brand tile, blurb, and a Connect / Connected control.
struct GoogleConnectionRow: View {
    @EnvironmentObject private var google: GoogleConnectionsModel
    let service: GoogleService

    var body: some View {
        HStack(spacing: 12) {
            ServiceIcon(systemImage: service.systemImage, color: service.brandColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName).font(.body)
                Text(service.blurb).font(.caption).foregroundStyle(.secondary)
                if google.isConnected(service) {
                    Text(service.capabilitySummary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var control: some View {
        if google.busy == service {
            ProgressView()
        } else if google.isConnected(service) {
            Menu {
                Button(role: .destructive) {
                    google.disconnect(service)
                } label: {
                    Label("Disconnect", systemImage: "minus.circle")
                }
            } label: {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        } else {
            Button("Connect") {
                google.connect(service)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!GoogleOAuthConfig.isConfigured || google.busy != nil)
        }
    }
}

/// Rounded brand tile. Placeholder styling until official brand icons (from
/// Google's brand resource pages) are added to the asset catalog.
struct ServiceIcon: View {
    let systemImage: String
    let color: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(color.opacity(0.15))
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            )
    }
}
