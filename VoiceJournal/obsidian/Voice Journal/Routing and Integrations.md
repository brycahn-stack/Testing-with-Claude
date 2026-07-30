---
tags: [project/voice-journal, integrations, architecture]
created: 2026-07-30
---

# Routing and Integrations

Part of [[Voice Journal]]. Implemented in `iOSApp/Routing/`.

Once a memo is classified (see [[Categorization Engine]]), the **Router** decides
where it goes and performs the hand-off.

## The `Destination` protocol

Every integration is one conformance:

```swift
protocol Destination {
    var id: String { get }
    var displayName: String { get }
    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool
    func route(_ entry: JournalEntry, _ result: CategorizationResult) async -> RoutingResult
}
```

Adding a new integration (e.g. Obsidian, Notion, HealthKit) means writing one of
these and registering it with the `Router`. Nothing else changes.

## Destinations today

| Destination | Handles | Mechanism | State |
|---|---|---|---|
| `CalendarDestination` | Schedule (has a time) | EventKit `EKEvent` | ✅ live |
| `RemindersDestination` | Task (no time) | EventKit `EKReminder` | ✅ live |
| `LogDestination.workout` | Workout | in-app typed log | 🟡 stub |
| `LogDestination.meal` | Meal | in-app typed log | 🟡 stub |
| `LogDestination.idea` | Business Idea | in-app typed log | 🟡 stub |
| `NoteDestination` | Note | kept in journal | ✅ |

## Router rules

- Destinations are tried in **priority order**; first that `canHandle` wins.
- **Low-confidence** classifications (< 0.5) are held with a `needsConfirmation`
  result instead of being auto-routed — never silently misfile.
- Auto-created **calendar events** are marked `needsConfirmation` too, since a
  guessed time deserves a human glance.

## What to build next

The stubbed logs and new apps are the growth area — the full menu of realistic
iOS targets and *how* each one connects is in [[iOS Integration Options]].
