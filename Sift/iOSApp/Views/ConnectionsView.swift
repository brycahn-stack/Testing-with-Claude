import SwiftUI
import UniformTypeIdentifiers
import SiftCore

/// The Connections tab: every service the app can hand memos to, with individual
/// connect/disconnect controls. System integrations (Reminders, Calendar) are
/// listed for transparency; Google services carry real OAuth state, and Obsidian
/// carries a folder grant.
struct ConnectionsView: View {
    @EnvironmentObject private var google: GoogleConnectionsModel
    @EnvironmentObject private var obsidian: ObsidianConnection
    @EnvironmentObject private var trust: TrustSettings

    @State private var showingVaultPicker = false

    /// Destinations the user can set a trust level for, in display order.
    /// `obsidian.profile` is deliberately absent: appending to a note you wrote
    /// is always high-stakes, so there'd be nothing to choose.
    private let trustable: [(id: String, name: String)] = [
        ("google.gmail", "Gmail"),
        ("google.calendar", "Google Calendar"),
        ("calendar", "Calendar"),
        ("reminders", "Reminders"),
        ("obsidian", "Obsidian"),
        ("log.workout", "Training Log"),
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

                obsidianSection

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
                    Text("“Auto when confident” lets Sift act without waiting, above \(Int(TrustSettings.autoApproveThreshold * 100))% confidence. Sending email, inviting people, and editing a note you wrote always wait for you, whatever this is set to.")
                }

                Section {
                    Text("Connections are granted individually with the narrowest scopes possible: Gmail can send mail and save drafts but cannot read your inbox, Google Calendar can only manage events, and Obsidian reaches exactly one folder — the vault you picked. Google tokens are stored in the iOS Keychain. Disconnect any time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connections")
            .onAppear { obsidian.refresh() }
            // Folder-scoped access: iOS hands back a security-scoped URL for the
            // vault and nothing else on the device.
            .fileImporter(
                isPresented: $showingVaultPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                obsidian.handlePickerResult(result)
            }
            .alert("Connection Error", isPresented: .init(
                get: { google.lastError != nil },
                set: { if !$0 { google.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(google.lastError ?? "")
            }
            .alert("Obsidian Error", isPresented: .init(
                get: { obsidian.lastError != nil },
                set: { if !$0 { obsidian.lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(obsidian.lastError ?? "")
            }
        }
    }

    // MARK: - Obsidian

    /// Obsidian has no API — a vault is a folder of Markdown. So "connecting" is
    /// picking that folder once, and the settings below are just *where in it*
    /// Sift is allowed to write.
    @ViewBuilder
    private var obsidianSection: some View {
        Section {
            HStack(spacing: 12) {
                ObsidianIcon()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Obsidian").font(.body)
                    Text("Write memos into your vault as Markdown.")
                        .font(.caption).foregroundStyle(.secondary)
                    if obsidian.isConnected {
                        Text(obsidian.capabilitySummary)
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                obsidianControl
            }
            .padding(.vertical, 4)

            if obsidian.isConnected {
                LabeledContent("Vault", value: obsidian.vaultName ?? "—")
                LabeledContent("Notes found") {
                    Text(obsidian.noteCount.map { "\($0)" } ?? "—")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("New notes in")
                    Spacer()
                    TextField("Vault root", text: $obsidian.settings.folder)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .frame(maxWidth: 160)
                }

                Toggle("Link to existing notes", isOn: $obsidian.settings.linkToExistingNotes)
            }
        } header: {
            Text("Obsidian")
        } footer: {
            Text(obsidian.isConnected
                 ? "Sift can only see the folder you picked. If your vault syncs through iCloud Drive, notes written here show up on your Mac on the next sync."
                 : "Pick your vault folder in Files. Works with any vault iOS can reach — iCloud Drive, On My iPhone, or another provider.")
        }

        if obsidian.isConnected {
            Section {
                Toggle("Remember facts about me", isOn: $obsidian.settings.profileCaptureEnabled)

                if obsidian.settings.profileCaptureEnabled {
                    HStack {
                        Text("Note")
                        Spacer()
                        TextField("About Me", text: $obsidian.settings.profileNoteName)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 160)
                    }
                    HStack {
                        Text("Under heading")
                        Spacer()
                        TextField("From Sift", text: $obsidian.settings.profileHeading)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .frame(maxWidth: 160)
                    }
                }
            } header: {
                Text("Profile note")
            } footer: {
                Text("“Remember that I work best in the mornings” gets added to that note as a dated bullet under that heading. This is the only case where Sift edits a file you already wrote, so it always asks first — and keeping every addition under one heading means you can review or delete them in one go.")
            }
        }
    }

    @ViewBuilder
    private var obsidianControl: some View {
        if obsidian.busy {
            ProgressView()
        } else if obsidian.isConnected {
            Menu {
                Button {
                    showingVaultPicker = true
                } label: {
                    Label("Change vault", systemImage: "folder")
                }
                Button(role: .destructive) {
                    obsidian.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "minus.circle")
                }
            } label: {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
            }
        } else {
            Button("Choose Vault") { showingVaultPicker = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
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
