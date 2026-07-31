import SwiftUI
import SiftCore

/// The confirmation step. Shows the action rendered the way the destination app
/// itself would show it — a Gmail compose window, a Calendar event editor — with
/// every field editable, then one unambiguous button that says exactly what will
/// happen ("Send", "Create Event").
///
/// Nothing has been created at this point. Closing the sheet costs nothing.
struct ActionPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var payload: ActionPayload
    let action: ProposedAction
    let onCommit: (ProposedAction) -> Void
    let onDismissAction: (ProposedAction) -> Void

    init(action: ProposedAction,
         onCommit: @escaping (ProposedAction) -> Void,
         onDismissAction: @escaping (ProposedAction) -> Void) {
        self.action = action
        self.onCommit = onCommit
        self.onDismissAction = onDismissAction
        _payload = State(initialValue: action.payload)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch payload {
                case .email(let draft):
                    GmailComposePreview(draft: Binding(
                        get: { draft },
                        set: { payload = .email($0) }
                    ))
                case .calendarEvent(let draft):
                    CalendarEventPreview(
                        draft: Binding(get: { draft }, set: { payload = .calendarEvent($0) }),
                        isGoogle: action.destinationID == "google.calendar"
                    )
                case .reminder(let draft):
                    ReminderPreview(draft: Binding(
                        get: { draft }, set: { payload = .reminder($0) }
                    ))
                case .logEntry(let draft):
                    LogPreview(draft: draft)
                case .note(let draft):
                    NotePreview(draft: draft)
                case .markdownNote(let draft):
                    ObsidianNotePreview(draft: Binding(
                        get: { draft }, set: { payload = .markdownNote($0) }
                    ))
                case .workoutLog(let draft):
                    WorkoutLogPreview(draft: Binding(
                        get: { draft }, set: { payload = .workoutLog($0) }
                    ))
                case .mealLog(let draft):
                    MealLogPreview(draft: Binding(
                        get: { draft }, set: { payload = .mealLog($0) }
                    ))
                }
            }
            .navigationTitle(action.destinationName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(payload.commitVerb) {
                        var committed = action
                        committed.payload = payload
                        onCommit(committed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCommit)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
    }

    /// Guard rails: an email with no valid recipient can't be sent, and an empty
    /// note is just litter in the vault.
    private var canCommit: Bool {
        switch payload {
        case .email(let draft):
            return draft.hasValidRecipient
        case .markdownNote(let draft):
            return !draft.noteName.trimmingCharacters(in: .whitespaces).isEmpty
                && !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return true
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if case .email(let draft) = payload, !draft.hasValidRecipient {
                Label("Add a recipient address to send this.", systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(role: .destructive) {
                    onDismissAction(action)
                    dismiss()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                Spacer()
                if let reasoning = action.reasoning {
                    Text(reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - Gmail

/// Styled after Gmail's compose window so the preview is recognizable at a glance.
struct GmailComposePreview: View {
    @Binding var draft: EmailDraft
    @State private var recipientField = ""

    private let gmailRed = Color(red: 0.92, green: 0.26, blue: 0.21)

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .foregroundStyle(gmailRed)
                    Text(draft.sendImmediately ? "New Message" : "Draft")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Picker("", selection: $draft.sendImmediately) {
                        Text("Send").tag(true)
                        Text("Save draft").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }

            Section {
                HStack {
                    Text("To").foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                    TextField(draft.recipientHint.map { "\($0)'s address" } ?? "name@example.com",
                              text: $recipientField)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: recipientField) { _, new in
                            draft.to = new
                                .split(whereSeparator: { $0 == "," || $0 == " " })
                                .map(String.init)
                                .filter { !$0.isEmpty }
                        }
                }
                HStack {
                    Text("Subject").foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                    TextField("Subject", text: $draft.subject)
                }
            } footer: {
                if let hint = draft.recipientHint, draft.to.isEmpty {
                    Text("Sift heard “\(hint)” but doesn't know their address — it won't guess. Enter it above.")
                }
            }

            Section("Message") {
                TextEditor(text: $draft.body)
                    .frame(minHeight: 180)
                    .font(.body)
            }
        }
    }
}

// MARK: - Calendar

/// Styled after a calendar event editor: title, time block, location, guests.
struct CalendarEventPreview: View {
    @Binding var draft: CalendarEventDraft
    let isGoogle: Bool

    private var accent: Color {
        isGoogle ? Color(red: 0.26, green: 0.52, blue: 0.96) : .red
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Circle().fill(accent).frame(width: 12, height: 12)
                    TextField("Event title", text: $draft.title)
                        .font(.title3.weight(.semibold))
                }
            }

            Section("When") {
                Toggle("All day", isOn: $draft.isAllDay)
                DatePicker("Starts", selection: $draft.start,
                           displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                if !draft.isAllDay {
                    DatePicker("Ends", selection: $draft.end,
                               in: draft.start...,
                               displayedComponents: [.date, .hourAndMinute])
                }
                HStack {
                    Text("Duration").foregroundStyle(.secondary)
                    Spacer()
                    Text(durationText).foregroundStyle(.secondary)
                }
            }

            Section("Details") {
                TextField("Location", text: Binding(
                    get: { draft.location ?? "" },
                    set: { draft.location = $0.isEmpty ? nil : $0 }
                ))
                TextField("Notes", text: Binding(
                    get: { draft.notes ?? "" },
                    set: { draft.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...6)
            }

            if !draft.invitees.isEmpty {
                Section("Guests") {
                    ForEach(draft.invitees, id: \.self) { guest in
                        Label(guest, systemImage: "person.crop.circle")
                    }
                    Text("Guests will be emailed an invitation.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Label(
                    isGoogle ? "Creates on your primary Google Calendar"
                             : "Creates on your default Apple Calendar",
                    systemImage: "calendar.badge.plus"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var durationText: String {
        let minutes = Int(draft.end.timeIntervalSince(draft.start) / 60)
        guard minutes > 0 else { return "—" }
        let h = minutes / 60, m = minutes % 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        return h > 0 ? "\(h)h" : "\(m)m"
    }
}

// MARK: - Simpler payloads

struct ReminderPreview: View {
    @Binding var draft: ReminderDraft
    @State private var hasDueDate: Bool

    init(draft: Binding<ReminderDraft>) {
        _draft = draft
        _hasDueDate = State(initialValue: draft.wrappedValue.dueDate != nil)
    }

    var body: some View {
        Form {
            Section {
                TextField("Reminder", text: $draft.title)
                    .font(.title3.weight(.medium))
            }
            Section("When") {
                Toggle("Due date", isOn: $hasDueDate)
                    .onChange(of: hasDueDate) { _, on in
                        draft.dueDate = on ? (draft.dueDate ?? Date().addingTimeInterval(3600)) : nil
                    }
                if hasDueDate {
                    DatePicker("Due", selection: Binding(
                        get: { draft.dueDate ?? Date() },
                        set: { draft.dueDate = $0 }
                    ))
                }
            }
            Section("Notes") {
                TextField("Notes", text: Binding(
                    get: { draft.notes ?? "" },
                    set: { draft.notes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(2...6)
            }
        }
    }
}

struct LogPreview: View {
    let draft: LogDraft

    var body: some View {
        Form {
            Section {
                Label(draft.summary, systemImage: draft.kind.systemImage)
                    .font(.body)
            }
            if !draft.fields.isEmpty {
                Section("Extracted") {
                    ForEach(draft.fields.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack {
                            Text(key.capitalized)
                            Spacer()
                            Text(value).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Text("Filed to your \(draft.kind.displayName.lowercased()) log inside Sift.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NotePreview: View {
    let draft: NoteDraft

    var body: some View {
        Form {
            Section(draft.title) {
                Text(draft.body)
            }
        }
    }
}
