# Sift

Talk to your wrist all day; your phone sorts it out.

Sift is an Apple Watch + iPhone app for **frictionless voice journaling**.
Tap the mic on your watch, say whatever's on your mind — a business idea, a task,
a meeting, a workout you just did, a meal you ate — and the phone companion
transcribes it, figures out what kind of thought it was, and files it in the right
place (Reminders, Calendar, or a typed log) without you ever opening an app.

The premise: sifting through your phone during a busy day is expensive, but
speaking a ten-second memo is nearly free. So capture constantly on the wrist, and
let the phone do the sorting in the background — the app does the sifting, which
is where the name comes from.

---

## How it works

```
┌──────────────┐   audio file over    ┌───────────────────────────────────────────┐
│  Apple Watch │   WatchConnectivity   │                  iPhone                   │
│              │  ───────────────────▶ │                                           │
│  ⏺ one-tap   │                        │  Transcribe → Categorize → Route → Store  │
│    mic       │                        │      (Speech)   (NL + rules)  (EventKit)  │
└──────────────┘                        └───────────────────────────────────────────┘
```

1. **Capture (watch).** `RecordingView` is a single big mic button. It records a
   compressed `.m4a` with `AVAudioRecorder` and queues it for the phone with
   `WCSession.transferFile` — which the system delivers even if the phone is
   asleep or out of range at the moment you speak.
2. **Transcribe (phone).** `SpeechTranscriber` runs Apple's on-device `Speech`
   recognizer, so memos never leave the device.
3. **Categorize (phone).** `KeywordCategorizer` (built on the `NaturalLanguage`
   framework + weighted keyword scoring + `NSDataDetector` for dates) maps the
   transcript onto one of: **Business Idea · Task · Schedule · Workout · Meal ·
   Note**, with a confidence score.
4. **Route (phone).** The `Router` picks a `Destination`:
   - **Task** (no time) → **Reminders** (`EventKit`)
   - **Schedule** / task with a time → **Calendar** event (`EventKit`)
   - **Workout / Meal / Business Idea** → typed in-app logs
   - Anything low-confidence is **held for review** instead of being auto-filed.
5. **Review (phone).** `InboxView` shows a feed with a "Needs Review" section up
   top. Tap any entry to see where it landed and correct the category, which
   re-routes it.

---

## Project layout

```
Sift/
├── project.yml                  # XcodeGen manifest (generates the .xcodeproj)
├── Shared/                      # SiftCore framework — iOS + watchOS
│   ├── Models/                  #   JournalEntry, JournalCategory, RoutingResult
│   ├── Services/Categorizer.swift
│   ├── Connectivity/            #   Shared WatchConnectivity message keys
│   └── Persistence/JournalStore.swift
├── WatchApp/                    # watchOS target
│   ├── Audio/                   #   AVAudioRecorder wrapper
│   ├── Connectivity/            #   Sends recordings to the phone
│   └── Views/RecordingView.swift
├── iOSApp/                      # iOS target
│   ├── Transcriber.swift        #   Speech framework (iOS only)
│   ├── EntryPipeline.swift      #   transcribe → categorize → route → store
│   ├── Connectivity/            #   Receives recordings
│   ├── Routing/                 #   Destination protocol + Reminders/Calendar/Log
│   └── Views/                   #   InboxView, EntryDetailView
└── Tests/                       # Unit tests for the categorizer + router
```

**Why the `SiftCore` framework?** The models, categorizer, and store are
platform-neutral and shared by both apps. Anything platform-specific — `Speech`
and `EventKit` (iOS only), `AVAudioRecorder` (watch capture) — lives in the app
targets, so the shared framework builds cleanly for watchOS.

---

## Build & run

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen), so the repo stays free of the
noisy, merge-conflict-prone `.pbxproj`.

```bash
brew install xcodegen          # once
cd Sift
xcodegen generate
open Sift.xcodeproj
```

Then in Xcode:

1. Select the **Sift** scheme and set your **Development Team**
   (Signing & Capabilities) — or edit `DEVELOPMENT_TEAM` in `project.yml`.
2. Run on a paired **iPhone + Apple Watch** (WatchConnectivity file transfer and
   microphone capture need real devices; the simulator can't pair mic + watch
   transfer end-to-end).
3. Grant Microphone, Speech Recognition, Reminders, and Calendar permissions when
   prompted.

Run the unit tests with **⌘U** (or `xcodebuild test -scheme Sift`).

> Requires Xcode 15+ (iOS 17 / watchOS 10 deployment targets) and XcodeGen 2.38+.

---

## Design decisions

- **On-device everything.** Transcription and categorization run locally. A voice
  journal is intimate; nothing is sent to a server in this MVP.
- **Explainable classification first.** The keyword categorizer is deterministic
  and debuggable — you can see exactly which phrases triggered a category. It's a
  strong baseline and an honest offline fallback.
- **Protocol seams for the smart stuff.** `Categorizer`, `Transcriber`, and
  `Destination` are protocols. Swapping the keyword classifier for an LLM, or
  adding a HealthKit / Notes / Things destination, is a single conformance —
  routing, storage, and UI don't change.
- **Never silently misfile.** Low-confidence entries are surfaced for review, and
  auto-created calendar events are marked *needs confirmation* rather than trusted
  blindly.

---

## Propose → confirm → execute

Sift never acts on a memo directly. Every destination splits in two:

- **`propose`** builds a typed, editable `ProposedAction` and has **no side
  effects** — safe to run unattended, including from a background wake.
- **`execute`** performs the real hand-off, and only runs after you approve.

That split is what makes an AI proposer safe: a wrong proposal is a card you
dismiss, not an email someone already received.

**The Review tab** is the commit-or-dismiss queue. Each card shows what would
happen, the memo it came from, and why Sift thinks so. Tapping *Review* opens a
confirmation sheet rendered the way the destination app itself would show it —
a Gmail compose window, a Calendar event editor — with every field editable
before you commit.

**Trust levels** (per destination, in Connections) are the dial between magic and
control: *always ask*, or *auto when confident* (≥80%). Two things ignore the
setting and always wait for you: **sending email** and **inviting people to
events**. "Approve all" skips those too.

**Recipient addresses are never guessed.** Sift extracts the *name* it heard
("Jordan") and leaves the To field empty — Send stays disabled until you supply a
real address. Guessing is how you email the wrong person.

## Assistant

A tab that can read your whole journal and answer questions about it — category
round-ups, weekly summaries, free-text search. It reaches the journal through a
single `JournalContext` choke point, which is the one place to audit AI access or
add redaction later.

It ships with `LocalQueryResponder`: deterministic, on-device, and useful today
(no model required). The `AssistantResponder` protocol is the seam for a real
model — the plan is Apple's **Foundation Models** framework (iOS 26), which runs
on-device with structured output, so journal contents never leave the phone. A
cloud model would be an explicit opt-in, never a default.

Like everything else, the assistant **proposes but never executes**: anything it
wants to do becomes a card in the Review queue.

---

## Google connections (Gmail + Google Calendar)

The iOS app has a **Connections** tab where Gmail and Google Calendar can each be
connected individually via OAuth (`ASWebAuthenticationSession` + PKCE — the
standard secretless mobile flow). Tokens live in the iOS Keychain; scopes are the
narrowest possible (Gmail: create drafts only, no reading mail; Calendar: manage
events only).

Once connected:

- **Gmail** — memos with email intent ("email Sarah about the deck") are composed
  into a real message that you review and then **send** (or save as a draft). The
  `gmail.compose` scope covers sending *and* drafting but grants **no read access
  to your inbox**.
- **Google Calendar** — scheduling memos create Google Calendar events instead of
  local ones; when disconnected, the destination declines and routing falls back
  to the local Apple calendar automatically.

Both scopes are "sensitive" in Google's tiering: usable with up to **100 test
users with no review**, and requiring standard OAuth verification (~10 days, but
*not* the heavier CASA security assessment) to ship publicly.

**One-time setup (required before Connect works):** create a free iOS OAuth
client in [Google Cloud Console](https://console.cloud.google.com) — enable the
Gmail + Calendar APIs, configure the consent screen (add yourself as a test
user), create an **iOS** OAuth client for bundle ID `com.brycahn.sift`,
and paste the client ID into `iOSApp/Google/GoogleService.swift`. Full steps are
in that file's header comment. The tile icons are styled placeholders — official
Gmail/Calendar logos must be downloaded from Google's brand resource pages and
dropped into the asset catalog.

---

## Roadmap

The MVP captures, sorts, and files. Natural next steps, roughly in priority order:

- [ ] **In-app AI assistant** — a chatbot that reads the journal, proposes actions
      per connection ("draft this email", "log this workout"), and shows a
      commit-or-dismiss list on launch. The `RoutingResult.needsConfirmation`
      status is the seed of that proposed-actions inbox.

- [ ] **LLM categorizer** — an `LLMCategorizer: Categorizer` that extracts richer
      structure (task due dates, workout sets/reps, meal macros) with a
      confidence the router already knows how to gate on.
- [ ] **HealthKit destinations** — log workouts (`HKWorkout`) and meals
      (`HKDietaryEnergy`, etc.) instead of in-app-only logs.
- [ ] **Notes / Things / Notion destinations** for business ideas and long-form
      thoughts.
- [ ] **On-watch live transcription** (populate `WCKeys.watchTranscript`) for
      instant confirmation before the phone ever sees the audio.
- [ ] **Confirmation loop** — a lightweight "did I get this right?" prompt for
      newly-created calendar events.
- [ ] **Complications & Shortcuts** — start a memo from a watch face complication
      or "Hey Siri, journal this."
- [ ] **SwiftData migration** for `JournalStore` once the schema settles.

---

## Status

This is an initial, buildable foundation: the full capture → transcribe →
categorize → route → review loop is implemented, with unit tests for the
classification and routing logic. It has **not** been compiled on an Apple
toolchain in this environment (Linux CI has no Swift/Xcode) — expect to run
`xcodegen generate` and build once in Xcode to shake out any environment-specific
signing or capability tweaks.
