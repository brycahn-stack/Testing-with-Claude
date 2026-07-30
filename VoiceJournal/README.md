# Voice Journal

Talk to your wrist all day; your phone sorts it out.

Voice Journal is an Apple Watch + iPhone app for **frictionless voice journaling**.
Tap the mic on your watch, say whatever's on your mind — a business idea, a task,
a meeting, a workout you just did, a meal you ate — and the phone companion
transcribes it, figures out what kind of thought it was, and files it in the right
place (Reminders, Calendar, or a typed log) without you ever opening an app.

The premise: sifting through your phone during a busy day is expensive, but
speaking a ten-second memo is nearly free. So capture constantly on the wrist, and
let the phone do the sorting in the background.

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
VoiceJournal/
├── project.yml                  # XcodeGen manifest (generates the .xcodeproj)
├── Shared/                      # VoiceJournalCore framework — iOS + watchOS
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

**Why the `VoiceJournalCore` framework?** The models, categorizer, and store are
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
cd VoiceJournal
xcodegen generate
open VoiceJournal.xcodeproj
```

Then in Xcode:

1. Select the **VoiceJournal** scheme and set your **Development Team**
   (Signing & Capabilities) — or edit `DEVELOPMENT_TEAM` in `project.yml`.
2. Run on a paired **iPhone + Apple Watch** (WatchConnectivity file transfer and
   microphone capture need real devices; the simulator can't pair mic + watch
   transfer end-to-end).
3. Grant Microphone, Speech Recognition, Reminders, and Calendar permissions when
   prompted.

Run the unit tests with **⌘U** (or `xcodebuild test -scheme VoiceJournal`).

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

## Roadmap

The MVP captures, sorts, and files. Natural next steps, roughly in priority order:

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
