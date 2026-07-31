import SwiftUI
import AuthenticationServices
import SiftCore

/// The sign-in screen — shown once at first launch, and any time from
/// Connections.
///
/// The copy is the design: an account is optional, the journal lives on the
/// phone either way, and "Continue without an account" is a first-class exit,
/// not a shamed footnote. A local-first app that walls itself off behind a
/// login would be spending trust to buy nothing.
struct AccountView: View {
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Wordmark
            VStack(spacing: 14) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.tint)
                    )
                Text("Sift")
                    .font(.largeTitle.weight(.bold))
                Text("Talk to your wrist all day.\nYour phone sorts it out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    accounts.completeAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)

                GoogleSignInButton()

                Button("Continue without an account") {
                    dismiss()
                }
                .font(.subheadline)
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)

            Text("Your journal stays on this phone either way. An account puts a name on your data and gets Sift ready for sync later — nothing needs it today.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.top, 18)
                .padding(.bottom, 20)
        }
        // Signing in is the other way out of this screen.
        .onChange(of: accounts.isSignedIn) { _, signedIn in
            if signedIn { dismiss() }
        }
        .alert("Sign-in Error", isPresented: .init(
            get: { accounts.lastError != nil },
            set: { if !$0 { accounts.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(accounts.lastError ?? "")
        }
    }
}

/// Google's button, in the app's placeholder style (official brand assets are a
/// ship-time task, same as the Gmail tile). Disabled — with an explanation, not
/// silently — until the OAuth client ID from SETUP.md lands.
private struct GoogleSignInButton: View {
    @EnvironmentObject private var accounts: AccountStore

    var body: some View {
        VStack(spacing: 6) {
            Button {
                accounts.signInWithGoogle()
            } label: {
                HStack(spacing: 8) {
                    if accounts.busy {
                        ProgressView()
                    } else {
                        Text("G")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96))
                    }
                    Text("Sign in with Google")
                        .font(.body.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.bordered)
            .disabled(!GoogleOAuthConfig.isConfigured || accounts.busy)

            if !GoogleOAuthConfig.isConfigured {
                Text("Available once the Google OAuth client is set up — see SETUP.md.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Connections tab pieces

/// The row at the top of Connections: a profile card when signed in, an
/// invitation when not.
struct AccountSection: View {
    @EnvironmentObject private var accounts: AccountStore
    @State private var showingSignIn = false

    var body: some View {
        Section {
            if let account = accounts.account {
                NavigationLink {
                    AccountDetailView(account: account)
                } label: {
                    HStack(spacing: 12) {
                        InitialsAvatar(initials: account.initials)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.displayTitle).font(.body)
                            if let email = account.email, email != account.displayTitle {
                                Text(email).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(account.provider.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Button {
                    showingSignIn = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.dashed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in").font(.body)
                            Text("Optional — everything works without it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showingSignIn) {
            AccountView()
        }
    }
}

/// Account details: preferences that belong to a person rather than a
/// connection, and the way out.
struct AccountDetailView: View {
    let account: UserAccount
    @EnvironmentObject private var accounts: AccountStore
    @Environment(\.dismiss) private var dismiss

    /// `HealthPreferences` is static storage; this mirrors it for SwiftUI.
    @State private var weightUnit = HealthPreferences.defaultWeightUnit

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    InitialsAvatar(initials: account.initials, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayTitle).font(.headline)
                        if let email = account.email {
                            Text(email).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Signed in with \(account.provider.displayName)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Picker("Weight unit", selection: $weightUnit) {
                    ForEach(WeightUnit.allCases, id: \.self) { unit in
                        Text(unit.shortName).tag(unit)
                    }
                }
                .onChange(of: weightUnit) { _, newValue in
                    HealthPreferences.defaultWeightUnit = newValue
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("Used when a memo doesn't say — “squat 100 for 5” logs in this unit. Saying “kilos” or “pounds” always wins.")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    accounts.signOut()
                    dismiss()
                }
            } footer: {
                Text("Signing out forgets who you are on this phone. It deletes nothing — your journal never belonged to the account.")
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Initials in a tinted circle — no photo handling, no image cache, just enough
/// to make the card feel owned.
struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [.accentColor.opacity(0.85), .accentColor.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            )
    }
}
