---
tags: [project/sift, moc]
created: 2026-07-30
aliases: [Sift App]
---

# 🎙️ Sift

> Talk to your wrist all day; your phone sorts it out.

An **Apple Watch + iPhone** app for frictionless voice journaling. Tap the mic on
the watch, say whatever's on your mind — a business idea, a task, a meeting, a
workout, a meal — and the phone companion transcribes it, figures out what kind of
thought it was, and files it in the right place (Reminders, Calendar, or a typed
log) without you ever opening an app.

**The premise:** sifting through your phone during a busy day is expensive, but
speaking a ten-second memo is nearly free. Capture constantly on the wrist; let
the phone do the sorting in the background.

**The name** comes from that premise, verbatim: the app does the sifting so you
don't have to. It also names the differentiator — every competitor stops at
recording and summarizing; Sift *moves things* into the places you already live.

## Map of content

- [[Architecture]] — how the watch, phone, and shared framework fit together
- [[Categorization Engine]] — how free speech becomes a category
- [[Routing and Integrations]] — where entries end up, and how to add destinations
- [[Assistant and Review Queue]] — propose → confirm → execute, and the AI seam
- [[iOS Integration Options]] — the full menu of apps we could connect to
- [[Roadmap]] — what's next
- [[Build and Setup]] — clone → generate → build

## Status at a glance

| Piece | State |
|---|---|
| Watch capture (one-tap mic) | ✅ built |
| Watch → phone transfer | ✅ built |
| On-device transcription | ✅ built |
| Categorizer (6 categories) | ✅ built |
| Reminders destination | ✅ live |
| Calendar destination | ✅ live |
| Propose → confirm → execute | ✅ built |
| Review queue + confirmation previews | ✅ built |
| Gmail send / Google Calendar | ✅ built, needs OAuth client ID |
| Assistant tab (journal Q&A) | ✅ built, local responder |
| AI model behind the assistant | ⏳ Foundation Models next |
| Workout / Meal / Idea | 🟡 in-app logs (stubbed) |
| Compiled on Apple toolchain | ⏳ first build in Xcode 26 |

## The pipeline in one line

`Watch mic → WatchConnectivity → Transcribe (Speech) → Categorize (NL + rules) → Route (EventKit) → Store → Review`

See [[Architecture]] for the detail.
