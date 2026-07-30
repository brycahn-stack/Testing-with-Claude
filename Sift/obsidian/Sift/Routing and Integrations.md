---
tags: [project/sift, integrations, architecture]
created: 2026-07-30
---

# Routing and Integrations

Part of [[Sift]]. Implemented in `iOSApp/Routing/`.

Once a memo is classified (see [[Categorization Engine]]), the **Router** decides
where it goes and performs the hand-off.

## The `Destination` protocol

Every integration is one conformance, split into two phases:

```swift
protocol Destination {
    var id: String { get }
    var displayName: String { get }
    func canHandle(_ entry: JournalEntry, _ result: CategorizationResult) -> Bool
    /// No side effects — safe to run unattended.
    func propose(_ entry: JournalEntry, _ result: CategorizationResult) async -> ProposedAction?
    /// The real hand-off; only runs after the user approves.
    func execute(_ action: ProposedAction) async -> RoutingResult
}
```

**Propose/execute is the safety model.** Nothing reaches Gmail or Calendar until
a human approves it, which is what makes an AI proposer viable — a wrong
proposal is a card you dismiss, not an email someone received. Returning `nil`
from `propose` means "declining", so the router falls through to the next
destination (how Google destinations shadow their Apple equivalents only while
connected).

Adding a new integration (e.g. Obsidian, Notion, HealthKit) means writing one of
these and registering it with the `Router`. Nothing else changes.

## Destinations today

| Destination | Handles | Mechanism | State |
|---|---|---|---|
| `GmailDestination` | Task with email intent | Gmail API (OAuth) — sends or drafts | ✅ built, needs OAuth client ID |
| `GoogleCalendarDestination` | Schedule (has a time) | Google Calendar API (OAuth) | ✅ built, needs OAuth client ID |
| `CalendarDestination` | Schedule (fallback) | EventKit `EKEvent` | ✅ live |
| `RemindersDestination` | Task (no time) | EventKit `EKReminder` | ✅ live |
| `ObsidianProfileDestination` | "Remember that I…" | appends to your `About Me` note | ✅ built |
| `ObsidianDestination` | Note, Business Idea | writes Markdown into a vault | ✅ built |
| `LogDestination.workout` | Workout | in-app typed log | 🟡 stub |
| `LogDestination.meal` | Meal | in-app typed log | 🟡 stub |
| `LogDestination.idea` | Business Idea (fallback) | in-app typed log | 🟡 stub |
| `NoteDestination` | Note (fallback) | kept in journal | ✅ |

Obsidian is the one destination that both reads and writes — see
[[Obsidian Connection]].

## Router rules

- Destinations are tried in **priority order**; the first that `canHandle`s the
  entry *and* returns a proposal wins.
- A destination returning `nil` is **declining** (e.g. Google Calendar when not
  connected), so the next one gets a turn — Google wins when connected, Apple
  otherwise.
- Proposals land in the **Review queue** (`ProposalStore`) as `.pending`.
- **Trust levels** decide what skips the queue: *always ask* vs *auto when
  confident* (≥80%). Sending email, inviting guests, and appending to a note you
  wrote are `isHighStakes` and never auto-approve, whatever the setting.

See [[Assistant and Review Queue]] for the confirmation UI.

## Google connections (Connections tab)

The iOS app has a **Connections** tab: Gmail and Google Calendar tiles, each
individually connectable via OAuth (`ASWebAuthenticationSession` + PKCE, tokens
in Keychain, minimal scopes — Gmail can only create drafts, Calendar only
events). Requires a one-time free iOS OAuth client from Google Cloud Console;
setup steps live in `iOSApp/Google/GoogleService.swift`.

## What to build next

The stubbed logs and new apps are the growth area — the full menu of realistic
iOS targets and *how* each one connects is in [[iOS Integration Options]].
