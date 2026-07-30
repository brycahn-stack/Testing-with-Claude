---
tags: [project/sift, architecture]
created: 2026-07-30
---

# Architecture

Part of [[Sift]].

## The flow

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
3. **Categorize (phone).** See [[Categorization Engine]].
4. **Route (phone).** See [[Routing and Integrations]].
5. **Review (phone).** `InboxView` shows a feed with a "Needs Review" section on
   top. Tap any entry to see where it landed and correct the category, which
   re-routes it.

## Three targets

| Target | Platform | Role |
|---|---|---|
| `SiftCore` | iOS + watchOS (framework) | Models, categorizer, store, WC keys — platform-neutral, shared |
| `Sift` | iOS (app) | Receives recordings, transcribes, categorizes, routes, UI |
| `SiftWatch` | watchOS (app) | The one-tap mic that captures memos |

**Why the shared framework?** The models, categorizer, and store are
platform-neutral and used by both apps. Anything platform-specific — `Speech` and
`EventKit` (iOS only), `AVAudioRecorder` (watch capture) — lives in the app
targets, so the core framework builds cleanly for watchOS.

## Key files

- `Shared/Models/` — `JournalEntry`, `JournalCategory`, `RoutingResult`
- `Shared/Services/Categorizer.swift` — the classifier
- `Shared/Persistence/JournalStore.swift` — JSON-backed, `ObservableObject`
- `iOSApp/EntryPipeline.swift` — orchestrates transcribe → categorize → route → store
- `iOSApp/Routing/` — `Destination` protocol + Reminders / Calendar / Log destinations
- `WatchApp/` — recorder, connectivity sender, recording view

## Design decisions

- **On-device everything.** Transcription and categorization run locally. A voice
  journal is intimate; nothing is sent to a server in this MVP.
- **Explainable classification first.** The keyword categorizer is deterministic
  and debuggable — a strong baseline and an honest offline fallback. See
  [[Categorization Engine]].
- **Protocol seams for the smart stuff.** `Categorizer`, `Transcriber`, and
  `Destination` are protocols, so swapping in an LLM or a new integration is a
  single conformance — routing, storage, and UI don't change.
- **Never silently misfile.** Low-confidence entries are surfaced for review, and
  auto-created calendar events are marked *needs confirmation*.
