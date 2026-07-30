---
tags: [project/sift, integrations, ios, research]
created: 2026-07-30
---

# iOS Integration Options

Part of [[Sift]]. Reference for wiring the app to other apps — see
[[Routing and Integrations]] for the code seam (`Destination`).

## The iOS reality check

iOS is **not** Android. An app cannot reach into another third-party app's
storage and read/write its data — Apple sandboxes every app. So "connect to the
apps on your phone" resolves into **three mechanisms**, and which applies depends
entirely on the target:

- **Path A — Apple's shared system frameworks.** Some "apps" are really shared
  system databases your app can be granted access to. The only path that's truly
  on-device, no internet, no other app's cooperation. (Reminders + Calendar live
  here already.)
- **Path B — Hooks the other app chooses to expose.** App Intents / Shortcuts,
  custom URL schemes, or the share sheet. You hand them an action to perform; you
  don't read their data. Depends on what that app's developer built.
- **Path C — The third party's cloud API (over the internet, with OAuth).**
  Notion, Todoist, Google, etc. You talk to their servers, not the app on the
  phone. Most powerful, most work (accounts, tokens, privacy).

## Tier 1 — Apple system frameworks (Path A) — best ROI

| Target | Framework | Category | Effort |
|---|---|---|---|
| Reminders | EventKit | Task | ✅ done |
| Calendar | EventKit | Schedule | ✅ done |
| Health (workouts) | HealthKit `HKWorkout` | Workout | Low–Med |
| Health (nutrition) | HealthKit dietary samples | Meal | Med (many fields) |
| Contacts | Contacts | "call/text Sarah" → resolve person | Low |
| Photos | PhotoKit | attach/reference | Low |

These need only a permission prompt — no accounts, no servers.

## Tier 2 — App hooks (Path B)

| Target | Mechanism | Notes |
|---|---|---|
| **Obsidian** | `obsidian://new?vault=…&file=…&content=…` URL, or write `.md` to a vault folder | Great for Business Idea / Note. See below. |
| Bear / Drafts | URL schemes / x-callback-url | Strong note apps with rich schemes |
| Things / OmniFocus | URL schemes | Task power-users |
| Anything | Share sheet + App Intents | Broadest, least structured |

## Tier 3 — Cloud APIs (Path C)

| Target | Auth | Category |
|---|---|---|
| Notion | OAuth | Idea / Note (databases!) |
| Todoist | OAuth / token | Task |
| Google Calendar / Tasks | OAuth | Schedule / Task |
| Google Sheets | OAuth | Meal / Workout logs as rows |

Most flexible, but you own accounts, token refresh, and a privacy story.

## Obsidian specifically

Because the vault is just a folder of Markdown files, there are two clean routes:

1. **Write `.md` files** into a user-chosen folder that lives inside their vault
   (e.g. an iCloud Drive folder the app is granted access to via a security-scoped
   bookmark). Most "native," fully offline.
2. **`obsidian://` URL scheme** (optionally the *Advanced URI* community plugin)
   to have Obsidian create/append the note. Simpler, but pops Obsidian to the
   foreground.

> Note: the current *one-time doc export* into the vault (this very note set) is a
> plain folder copy on the Mac — not the same thing as the in-app Obsidian
> destination above, which is a [[Roadmap]] item.

## Recommended order

1. **HealthKit** (workouts, then meals) — unlocks two stubbed categories with a
   Tier-1 permission prompt, no accounts.
2. **Obsidian / a notes destination** — turns Business Idea + Note into real,
   searchable notes.
3. **An LLM categorizer** — richer extraction feeds better-structured destinations.
4. **Cloud APIs** only where a system framework can't do the job.
