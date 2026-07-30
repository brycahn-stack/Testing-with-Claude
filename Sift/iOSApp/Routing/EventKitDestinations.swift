import Foundation
import EventKit
import SiftCore

/// Shared, lazily-authorized `EKEventStore`. Both the Reminders and Calendar
/// destinations use one store instance.
actor EventKitAccess {
    static let shared = EventKitAccess()
    let store = EKEventStore()

    func requestReminders() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToReminders()) ?? false
        } else {
            return await withCheckedContinuation { c in
                store.requestAccess(to: .reminder) { granted, _ in c.resume(returning: granted) }
            }
        }
    }

    func requestCalendar() async -> Bool {
        if #available(iOS 17.0, *) {
            return (try? await store.requestFullAccessToEvents()) ?? false
        } else {
            return await withCheckedContinuation { c in
                store.requestAccess(to: .event) { granted, _ in c.resume(returning: granted) }
            }
        }
    }
}

/// Turns task-style memos ("remind me to call the dentist") into Reminders.
struct RemindersDestination: Destination {
    let id = "reminders"
    let displayName = "Reminders"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        // Tasks without a specific time become reminders; timed ones go to Calendar.
        result.category == .task && result.detectedDates.isEmpty
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .reminder(ReminderDraft(
                title: TitleBuilder.cleanTitle(from: entry.transcript),
                notes: entry.transcript,
                dueDate: result.detectedDates.first
            )),
            reasoning: "Sounds like a to-do with no specific time.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        guard case .reminder(let draft) = action.payload else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Wrong payload type")
        }
        guard await EventKitAccess.shared.requestReminders() else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Reminders access denied")
        }
        let store = await EventKitAccess.shared.store
        let reminder = EKReminder(eventStore: store)
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.calendar = store.defaultCalendarForNewReminders()
        if let due = draft.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: due
            )
        }

        do {
            try store.save(reminder, commit: true)
            return .init(destinationID: id, destinationName: displayName, status: .success,
                         detail: "Reminder: \(draft.title)", externalID: reminder.calendarItemIdentifier)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }
}

/// Turns scheduling memos ("meeting tomorrow at 3") into Apple Calendar events.
/// Acts as the fallback when Google Calendar isn't connected.
struct CalendarDestination: Destination {
    let id = "calendar"
    let displayName = "Calendar"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .schedule && !result.detectedDates.isEmpty
    }

    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction? {
        guard let start = result.detectedDates.first else { return nil }
        return ProposedAction(
            entryID: entry.id,
            destinationID: id,
            destinationName: displayName,
            payload: .calendarEvent(CalendarEventDraft(
                title: TitleBuilder.cleanTitle(from: entry.transcript),
                start: start,
                // Default one-hour block; adjustable in the confirmation sheet.
                end: start.addingTimeInterval(3600),
                notes: entry.transcript
            )),
            reasoning: "Heard a specific time, so this looks like a calendar event.",
            confidence: result.confidence
        )
    }

    func execute(_ action: ProposedAction) async -> RoutingResult {
        guard case .calendarEvent(let draft) = action.payload else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Wrong payload type")
        }
        guard await EventKitAccess.shared.requestCalendar() else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Calendar access denied")
        }
        let store = await EventKitAccess.shared.store
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.notes = draft.notes
        event.startDate = draft.start
        event.endDate = draft.end
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent, commit: true)
            return .init(destinationID: id, destinationName: displayName, status: .success,
                         detail: "\(draft.title) — \(draft.start.formatted(date: .abbreviated, time: .shortened))",
                         externalID: event.eventIdentifier)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }
}
