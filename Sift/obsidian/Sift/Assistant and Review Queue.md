---
tags: [project/sift, architecture, ai]
created: 2026-07-30
---

# Assistant and Review Queue

Part of [[Sift]]. The commit-or-dismiss layer, and where the AI plugs in.

## The core principle

**The proposer never executes.** Whatever decides what should happen — today the
keyword categorizer, later a model — emits a `ProposedAction`. A human approves.
Only then does anything reach Gmail, Calendar, or Reminders.

A wrong proposal is a card you dismiss. A wrong *execution* is an email someone
already received. That asymmetry is the whole argument for the design.

## Review tab (inbox, not chatbot)

Deliberately an inbox. The premise of Sift is that you *don't* sit and interact
with your phone — so opening the app shows a queue you glance at and approve, not
a conversation you have to start.

- One card per proposed action, showing the action, the memo it came from, and a
  plain-language "why I think this".
- **Approve all** for the safe majority — skips anything high-stakes.
- Tapping *Review* opens the confirmation sheet.

## Confirmation previews

The sheet renders the action the way the destination app itself would:

- **Gmail** → a compose window: To / Subject / body, a Send-vs-Save-draft toggle,
  everything editable.
- **Calendar** → an event editor: title, start/end with live duration, location,
  notes, guests, and which calendar it lands on.
- Reminders / logs / notes get simpler equivalents.

**Recipient addresses are never guessed.** Sift extracts the *name* it heard
("Jordan") and shows it as a prompt, leaving To empty. Send stays disabled until
a real address is entered. Guessing is how you email the wrong person.

## Trust levels

Per destination, set in Connections — the dial between magic and control:

| Level | Behavior |
|---|---|
| Always ask | Every action waits for approval. Default for Gmail + Calendar. |
| Auto when confident | Runs on its own above 80% confidence. Default for reminders and logs. |

Two things ignore the setting entirely and **always** wait: sending email, and
inviting people to events (`ProposedAction.isHighStakes`).

## Assistant tab

Reads the whole journal through a single `JournalContext` choke point — one place
to audit AI access, one place to add redaction later.

Ships with `LocalQueryResponder`: deterministic, on-device, no model needed.
Handles category round-ups ("what business ideas have I had?"), weekly summaries,
pending-queue questions, and free-text search. It's genuinely useful now and
stays the offline fallback later.

**The model plan:** Apple's **Foundation Models** framework (iOS 26) — on-device,
free, with guided generation that emits structured Swift types directly, which is
exactly what typed `ActionPayload`s need. Journal contents never leave the phone.
A cloud model would be an explicit opt-in.

Where a model earns its keep over keywords:
- **Splitting** one rambling memo into several actions.
- **Extraction** — sets/reps, calories/macros — which is what unlocks the
  stubbed HealthKit destinations.
- **Cross-entry insight** — "you've circled back to this idea four times."

## Background generation

Proposals should be built during the **background wake** when a memo arrives from
the watch, not when you open the app. `WCSession.transferFile` launches the iOS
app in the background, so the queue is already waiting by the time you look.

Caveats: force-quitting the app suppresses background launch; the wake window is
short (needs a `beginBackgroundTask` assertion around the pipeline — **not yet
added**); and the app must be launched once after install or reboot.
