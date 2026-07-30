import Foundation
import EventKit
import VoiceJournalCore

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

    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult {
        guard await EventKitAccess.shared.requestReminders() else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Reminders access denied")
        }
        let store = await EventKitAccess.shared.store
        let reminder = EKReminder(eventStore: store)
        reminder.title = TitleBuilder.cleanTitle(from: entry.transcript)
        reminder.notes = entry.transcript
        reminder.calendar = store.defaultCalendarForNewReminders()

        do {
            try store.save(reminder, commit: true)
            return .init(destinationID: id, destinationName: displayName, status: .success,
                         detail: "Reminder: \(reminder.title ?? "")", externalID: reminder.calendarItemIdentifier)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }
}

/// Turns scheduling memos ("meeting tomorrow at 3") into Calendar events.
struct CalendarDestination: Destination {
    let id = "calendar"
    let displayName = "Calendar"

    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool {
        result.category == .schedule && !result.detectedDates.isEmpty
    }

    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult {
        guard let start = result.detectedDates.first else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "No date detected")
        }
        guard await EventKitAccess.shared.requestCalendar() else {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: "Calendar access denied")
        }
        let store = await EventKitAccess.shared.store
        let event = EKEvent(eventStore: store)
        event.title = TitleBuilder.cleanTitle(from: entry.transcript)
        event.notes = entry.transcript
        event.startDate = start
        // Default one-hour block; the user can adjust it in Calendar.
        event.endDate = start.addingTimeInterval(3600)
        event.calendar = store.defaultCalendarForNewEvents

        // Created but flagged for confirmation — auto-creating calendar events from
        // a guessed time deserves a human glance before it's trusted.
        do {
            try store.save(event, span: .thisEvent, commit: true)
            return .init(destinationID: id, destinationName: displayName, status: .needsConfirmation,
                         detail: "Event: \(event.title ?? "") @ \(start.formatted(date: .abbreviated, time: .shortened))",
                         externalID: event.eventIdentifier)
        } catch {
            return .init(destinationID: id, destinationName: displayName, status: .failed,
                         detail: error.localizedDescription)
        }
    }
}

/// Small helper to make a tidy title from a raw transcript.
enum TitleBuilder {
    static func cleanTitle(from transcript: String, maxWords: Int = 8) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common lead-ins so "remind me to call mom" becomes "Call mom".
        for prefix in ["remind me to ", "remind me ", "i need to ", "i have to ", "don't forget to ", "note to self "] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        let words = text.split(separator: " ").prefix(maxWords).joined(separator: " ")
        let title = words.isEmpty ? text : words
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}
