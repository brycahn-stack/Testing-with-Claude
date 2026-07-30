---
tags: [project/sift, roadmap]
created: 2026-07-30
---

# Roadmap

Part of [[Sift]]. The MVP captures, sorts, and files. Next steps, roughly
in priority order:

- [ ] **Finish Google connections** — the Connections tab, OAuth flow, Gmail
      draft + Google Calendar destinations are built; needs a Google Cloud OAuth
      client ID pasted into `GoogleService.swift`, then a device test.
- [ ] **In-app AI assistant** — a chatbot that reads the journal, proposes
      actions per connection, and shows a commit-or-dismiss list on launch.
      `RoutingResult.needsConfirmation` is the seed of that proposed-actions
      inbox.

- [ ] **HealthKit destinations** — log workouts (`HKWorkout`) and meals
      (dietary samples) instead of in-app-only logs. Unlocks two stubbed
      categories. See [[iOS Integration Options]].
- [ ] **Obsidian / notes destination** — write Business Idea + Note entries into a
      vault as Markdown (URL scheme or folder write).
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

- Workout / Meal / Idea only file into in-app logs (no external destination yet).
- No transcript editing or audio playback.
- Not yet compiled on an Apple toolchain — first build happening in Xcode 26.
  See [[Build and Setup]].
