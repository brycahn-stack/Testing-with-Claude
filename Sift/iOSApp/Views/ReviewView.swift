import SwiftUI
import SiftCore

/// The commit-or-dismiss queue. Everything Sift wants to do, waiting on you.
///
/// Deliberately an inbox rather than a conversation: the point of the app is that
/// you *don't* have to sit and interact with it. Open, glance, approve, done.
struct ReviewView: View {
    @EnvironmentObject private var store: JournalStore
    @EnvironmentObject private var proposals: ProposalStore
    @EnvironmentObject private var pipeline: EntryPipeline
    @EnvironmentObject private var trust: TrustSettings

    @State private var previewing: ProposedAction?
    @State private var isApprovingAll = false

    var body: some View {
        NavigationStack {
            Group {
                if proposals.pending.isEmpty {
                    emptyState
                } else {
                    List {
                        if safeToApproveAll.count > 1 {
                            Section {
                                Button {
                                    approveAll()
                                } label: {
                                    Label("Approve all \(safeToApproveAll.count)", systemImage: "checkmark.circle.fill")
                                        .fontWeight(.semibold)
                                }
                                .disabled(isApprovingAll)
                            } footer: {
                                Text("Skips anything that sends email or invites people — those always get an individual look.")
                            }
                        }

                        Section("Waiting on you") {
                            ForEach(proposals.pending) { action in
                                ProposalCard(
                                    action: action,
                                    sourceText: store.entry(withID: action.entryID)?.transcript,
                                    onReview: { previewing = action },
                                    onQuickApprove: { Task { await pipeline.approve(action) } },
                                    onDismiss: { pipeline.dismiss(action) }
                                )
                            }
                        }

                        if !proposals.resolved.isEmpty {
                            Section("Recently done") {
                                ForEach(proposals.resolved.prefix(8)) { action in
                                    ResolvedRow(action: action)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review")
            .sheet(item: $previewing) { action in
                ActionPreviewSheet(
                    action: action,
                    onCommit: { edited in Task { await pipeline.approve(edited) } },
                    onDismissAction: { pipeline.dismiss($0) }
                )
            }
        }
    }

    /// Batch approval never covers high-stakes actions — sending mail or
    /// inviting people is exactly what you'd regret rubber-stamping.
    private var safeToApproveAll: [ProposedAction] {
        proposals.pending.filter { !$0.isHighStakes }
    }

    private func approveAll() {
        isApprovingAll = true
        Task {
            for action in safeToApproveAll {
                await pipeline.approve(action)
            }
            isApprovingAll = false
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("All clear", systemImage: "checkmark.circle")
        } description: {
            Text("Nothing waiting. New memos from your watch show up here as actions you can approve.")
        }
    }
}

/// One proposed action, with its source memo and the two decisions you can make.
struct ProposalCard: View {
    let action: ProposedAction
    let sourceText: String?
    let onReview: () -> Void
    let onQuickApprove: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: action.payload.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(action.payload.headline)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(action.destinationName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if action.isHighStakes {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Needs your confirmation")
                }
            }

            detailLine

            if let sourceText {
                Text("“\(sourceText)”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button(action.isHighStakes ? "Review & \(action.payload.commitVerb)" : "Review") {
                    onReview()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if !action.isHighStakes {
                    Button(action.payload.commitVerb, action: onQuickApprove)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

                Spacer()

                Button(role: .destructive, action: onDismiss) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.vertical, 6)
        // The whole card isn't a button — the actions are — so taps can't
        // accidentally commit something.
        .buttonStyle(.plain)
    }

    /// The one line that tells you what actually happens if you say yes.
    @ViewBuilder
    private var detailLine: some View {
        switch action.payload {
        case .email(let d):
            Label(
                d.to.isEmpty ? "No recipient yet" : d.to.joined(separator: ", "),
                systemImage: d.to.isEmpty ? "person.crop.circle.badge.questionmark" : "person.crop.circle"
            )
            .font(.caption)
            .foregroundStyle(d.to.isEmpty ? .orange : .secondary)
        case .calendarEvent(let d):
            Label(
                d.start.formatted(date: .abbreviated, time: .shortened),
                systemImage: "clock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .reminder(let d):
            if let due = d.dueDate {
                Label(due.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case .markdownNote(let d):
            Label(
                d.mode.isAppend ? "Edits \(d.fileName)" : d.vaultPath,
                systemImage: d.mode.isAppend ? "square.and.pencil" : "folder"
            )
            .font(.caption)
            // An edit to a file the user wrote is worth a second look.
            .foregroundStyle(d.mode.isAppend ? .orange : .secondary)
        case .logEntry, .note:
            EmptyView()
        }
    }

    private var tint: Color {
        switch action.payload {
        case .email:         return Color(red: 0.92, green: 0.26, blue: 0.21)
        case .calendarEvent: return action.destinationID == "google.calendar"
            ? Color(red: 0.26, green: 0.52, blue: 0.96) : .red
        case .reminder:      return .orange
        case .logEntry:      return .green
        case .note:          return .gray
        case .markdownNote:  return ObsidianMark.purple
        }
    }
}

struct ResolvedRow: View {
    let action: ProposedAction

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.payload.headline)
                    .font(.subheadline)
                    .lineLimit(1)
                if let detail = action.result?.detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private var icon: String {
        switch action.status {
        case .completed: return "checkmark.circle.fill"
        case .dismissed: return "xmark.circle.fill"
        case .failed:    return "exclamationmark.triangle.fill"
        default:         return "clock"
        }
    }

    private var color: Color {
        switch action.status {
        case .completed: return .green
        case .dismissed: return .secondary
        case .failed:    return .red
        default:         return .secondary
        }
    }
}
