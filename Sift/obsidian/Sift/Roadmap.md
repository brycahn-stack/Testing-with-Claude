---
tags: [project/sift, roadmap]
created: 2026-07-30
---

# Roadmap

Part of [[Sift]]. The MVP captures, sorts, and files. Next steps, roughly
in priority order:

- [ ] **Finish Google connections** — Connections tab, OAuth, Gmail send +
      Google Calendar destinations are built; needs a Google Cloud OAuth client
      ID pasted into `GoogleService.swift`, then a device test.
- [ ] **Real model behind the Assistant** — Apple Foundation Models (iOS 26)
      replacing `LocalQueryResponder`, emitting typed `ActionPayload`s straight
      into the Review queue. See [[Assistant and Review Queue]].
- [ ] **Background task assertion** — wrap the ingest pipeline in
      `beginBackgroundTask` so proposals finish generating during the watch
      hand-off wake instead of being truncated.

- [x] **Obsidian destination** — Business Idea + Note entries write into a vault
      as Markdown, with wikilinks and an "About Me" append. See
      [[Obsidian Connection]].
- [ ] **HealthKit destinations** — log workouts (`HKWorkout`) and meals
      (dietary samples) instead of in-app-only logs. Unlocks two stubbed
      categories. See [[iOS Integration Options]].
- [ ] **Assistant reads the vault** — the vault is already readable, so letting
      the assistant answer from notes as well as journal entries is mostly a
      `JournalContext` change.
- [ ] **LLM categorizer** — an `LLMCategorizer: Categorizer` that extracts richer
      structure (task due dates, workout sets/reps, meal macros) with a confidence
      the router already knows how to gate on. See [[Categorization Engine]].
- [ ] **Notion / Todoist / Google** cloud destinations for power users.
- [ ] **On-watch live transcription** (populate `WCKeys.watchTranscript`) for
      instant confirmation before the phone sees the audio.
- [ ] **Confirmation loop** — a lightweight "did I get this right?" prompt for
      newly-created calendar events.
- [ ] **Complications & Shortcuts** — start a memo from a watch face complication
      or "Hey Siri, journal this."
- [ ] **Transcript editing + audio playback** in the entry detail view.
- [ ] **SwiftData migration** for `JournalStore` once the schema settles.

## Known gaps right now

- Workout / Meal only file into in-app logs (no external destination yet).
- Obsidian writes standalone files; no daily-note append or template support.
- No transcript editing or audio playback.
- Not yet compiled on an Apple toolchain — first build happening in Xcode 26.
  See [[Build and Setup]].
