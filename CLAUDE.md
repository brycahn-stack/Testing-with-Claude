# Sift — orientation for Claude

Read this before touching anything. It explains what the app is, how each piece
works, and — most importantly — **which rules must not be broken**, because
several of them look like arbitrary friction until you know why they're there.

The project lives in `Sift/`. Everything below is relative to that folder.

---

## What Sift is

An **Apple Watch + iPhone voice journal that files itself.**

You tap a mic on your watch and say anything — a task, an idea, a meeting, the
sets you just lifted, what you ate. The phone transcribes it on-device, works
out what kind of thought it was, and routes it to where it actually belongs:
Reminders, Calendar, Gmail, an Obsidian vault, or a structured training log.

The premise: pulling out your phone costs enough that most thoughts never get
captured. Speaking for ten seconds costs almost nothing. So capture constantly
on the wrist and let the phone do the sorting — the app does the *sifting*,
which is where the name comes from.

The differentiator: every competitor stops at recording and summarizing. Sift
**moves things into the places you already live.**

---

## The one idea everything else depends on

**The proposer never executes.**

Every destination splits in two:

- **`propose()`** builds a typed, editable `ProposedAction`. **Zero side
  effects.** Safe to run unattended, including from a background wake.
- **`execute()`** performs the real hand-off, and only runs after the user
  approves.

A wrong proposal is a card you swipe away. A wrong *execution* is an email
someone already received. That asymmetry is the entire argument for the design,
and it's what makes it safe to eventually put a language model in the proposer's
seat.

**If you add a destination, or an AI feature, it proposes. It does not act.**

---

## Project shape

Three targets, generated from `project.yml` by **XcodeGen**:

| Target | Type | Contains |
|---|---|---|
| `SiftCore` | framework (iOS + watchOS) | `Shared/` — models, stores, categorizer, extractor |
| `Sift` | iOS app | `iOSApp/` — pipeline, destinations, all UI |
| `SiftWatch` | watchOS app | `WatchApp/` — mic capture, transfer |
| `SiftTests` | unit tests | `Tests/` |

`SiftCore` must compile for **watchOS as well as iOS**, so nothing
platform-specific goes in `Shared/`. `Speech`, `EventKit`, and `HealthKit` live
in the iOS target; `AVAudioRecorder` capture lives in the watch target.

### `.xcodeproj` is generated, never committed

```bash
cd Sift && xcodegen generate && open Sift.xcodeproj
```

**Do not edit build settings in Xcode's UI** — they're overwritten on the next
generate. Edit `project.yml` and regenerate. Same for `Info.plist` and
`Sift.entitlements`, which XcodeGen writes from `project.yml` and `.gitignore`
excludes.

Source files are picked up by folder glob, so **adding a `.swift` file needs no
project change** — only `project.yml` edits require re-running `xcodegen`.

---

## The pipeline, end to end

```
Watch mic
  → WCSession.transferFile          (queued; survives phone asleep / out of range)
  → SpeechTranscriber               (on-device, iOS only)
  → KeywordCategorizer              (NaturalLanguage + weighted keywords + NSDataDetector)
  → Router.propose()                (no side effects)
  → ProposalStore                   (.pending)
  → [ user approves, or trust auto-approves ]
  → Router.execute()                (the real hand-off)
  → JournalStore / HealthLogStore
```

`EntryPipeline.swift` orchestrates all of it. Note what it does *not* do:
perform side effects. That's why it's safe to run from a background wake.

---

## Subsystems

### Capture and transfer

- `WatchApp/Views/RecordingView.swift` — one big mic button, nothing else.
- `WatchApp/Audio/WatchAudioRecorder.swift` — records compressed `.m4a`.
- `WCSession.transferFile` is deliberate: the system delivers it even if the
  phone is asleep or out of range when you speak, and **launches the iOS app in
  the background** to receive it.
- `PhoneSessionManager.swift` receives and hands to `EntryPipeline`.

**Not on the simulator.** WatchConnectivity, the mic, and transcription need
real paired devices. Use the compose button (below) to test on a simulator.

### Categorization

`Shared/Services/Categorizer.swift`. Six categories: Business Idea, Task,
Schedule, Workout, Meal, Note.

Deterministic and explainable on purpose — weighted keyword scoring plus
`NSDataDetector` for dates. Multi-word phrases score higher than lone words. A
concrete date/time pushes hard toward `.schedule`; a task that names a specific
time *becomes* a schedule.

`Categorizer` is a **protocol**. Swapping in a model is one conformance and
touches nothing else. `KeywordCategorizer` stays as the offline fallback.

### Routing

`iOSApp/Routing/Destination.swift` defines the protocol. `Router.swift` tries
destinations **in priority order**; the first that both `canHandle`s the entry
*and* returns a proposal wins.

**Returning `nil` from `propose` means "declining"** — the router falls through
to the next destination. This is how connected services shadow their local
equivalents: Google Calendar sits ahead of Apple Calendar and declines when
disconnected, so scheduling memos fall back automatically. Same for Obsidian
over the in-app idea log.

Current order (from `Router.init`):

```
ObsidianProfileDestination   "remember that I…"      → About Me note
ObsidianPersonDestination    "Sarah mentioned…"      → that person's note
GmailDestination             task with email intent
GoogleCalendarDestination    schedule, if connected
CalendarDestination          schedule (EventKit fallback)
RemindersDestination         task without a time
ObsidianDestination          note / business idea, if a vault is connected
WorkoutDestination           workout  → Health store
MealDestination              meal     → Health store
LogDestination.idea          business idea (fallback)
NoteDestination              note (fallback)
```

The two Obsidian intent destinations lead because otherwise "remember that I
prefer mornings" reads as a task and lands in Reminders.

### Proposals and trust

`Shared/Models/ProposedAction.swift` — a typed `ActionPayload` enum: `email`,
`calendarEvent`, `reminder`, `logEntry`, `note`, `markdownNote`, `workoutLog`,
`mealLog`. Typed rather than free text so the confirmation UI can render a real
preview and the user can fix individual fields.

`Shared/Models/TrustSettings.swift` — per destination, either *always ask* or
*auto when confident* (≥ 80%).

**Three things ignore that setting and always wait** (`isHighStakes`):

1. Sending email
2. Inviting people to a calendar event
3. Appending to a note the user wrote

The first two are visible to other people. The third edits the user's own prose.
`canAutoApprove` checks `isHighStakes` first and no setting overrides it.

### Confirmation UI

`Views/ReviewView.swift` is a commit-or-dismiss **inbox**, not a chatbot —
deliberately, because the premise is that you *don't* sit interacting with your
phone. Each card shows the action, the memo it came from, and a plain-language
"why I think this".

`Views/ActionPreviewSheet.swift` renders each payload **the way the destination
app itself would**: a Gmail compose window, a Calendar event editor, the literal
Markdown file. Every field editable before committing.

### Health

`Shared/Models/HealthLog.swift`, `Shared/Services/SetExtractor.swift`,
`iOSApp/Health/HealthKitService.swift`, `Views/HealthView.swift`.

**Why training data lives in Sift and not Apple Health:** HealthKit models
*sessions and quantities*. It can hold "45 minutes of strength training, 320
kcal" but has **no data type for reps, sets, or weight lifted**. Custom metadata
on a workout sample is a private blob the Health app won't display and no other
app can read. This is why every serious lifting app keeps its own database.

Ownership splits three ways:

| Layer | Owner |
|---|---|
| Duration, heart rate, calories | **The watch** — Sift reads via HealthKit, never writes |
| Exercises, sets, reps, weight | **Sift** — nowhere else can represent it |
| How it felt | **The voice memo** |

**Sift never writes a workout to HealthKit.** It would duplicate the session the
watch already recorded *and* credit invented calories to the user's Activity
rings. The entitlement requests read access and an **empty share set**.
`HealthKitService` matches a logged session to the watch's workout by timestamp
(nearest end date, ±4h) and attaches its numbers.

**`SetExtractor` is rules, not a model** — gym language is a rigid little grammar
over a bounded vocabulary. It handles `5x5 at 225`, `three sets of eight`,
`225 for 5`, `8, 8, 6 at 185`, `two twenty five` → 225, `did 20 pushups`,
kilograms, and ~25 exercise names with aliases.

Two disambiguation rules carry most of it:
- **The 40 lb threshold.** In "A x B", a leading number ≥ 40 is a weight
  (`225 x 5`); below it, a set count (`5 x 5`). An empty barbell is 45 lb.
- **Adjacent spoken numbers merge only when the middle token is a round ten**,
  which is what stops "3 sets of 8" collapsing into 38.

**The contract when it fails: nothing invented, nothing lost.** No exercises
parsed → `WorkoutLog.isUnstructured` is true and the raw transcript is shown. A
wrong number in a training log is worse than no number, because you'd train off
it.

Meals are the mirror image: HealthKit *does* have a home for them
(`HKCorrelation` of type `.food`), but "a chicken salad" carries no calorie
count. **Macros are recorded only when stated outright.** Estimating them is the
first feature here that genuinely needs a model.

### Obsidian

`iOSApp/Obsidian/ObsidianVault.swift` (an `actor`), plus three destinations.

Unlike Gmail there's no API and no OAuth — **a vault is just a folder of
Markdown**. The user picks the folder once, iOS returns a **security-scoped
bookmark**, and that bookmark *is* the connection. Access is genuinely two-way,
which buys two things:

- **Wikilinks that resolve.** `ObsidianLinker` only links to notes it has seen
  in the vault index. It will never invent a `[[link]]` and leave an empty node
  in the user's graph.
- **Appending to notes they already keep** — `About Me`, or a person's page.

Implementation notes that matter:
- **`NSFileCoordinator` on every read and write.** A synced folder can be written
  by the sync daemon mid-edit; uncoordinated writes lose paragraphs. The append
  is a read-modify-write inside one coordinated block.
- **Never overwrites** — a clashing filename gets ` 2`, ` 3`, ….
- **Stale bookmarks self-heal** rather than forcing the user to re-pick.
- `MarkdownNoteDraft` **owns its own rendering**, so the confirmation sheet
  previews the literal bytes headed for disk. Don't add a second rendering path.

The two intent matchers (`ObsidianProfileIntent`, `ObsidianPersonIntent`) are
deliberately narrow and reject anything action-shaped — "remember that I need to
call the bank" is a to-do, not a fact about you. Missing a match costs nothing
(it becomes an ordinary note); a false match corrupts the user's own writing.
`ObsidianPersonIntent` matches on the **raw transcript**, not a lowercased copy,
because capitalization is the only signal separating "Sarah mentioned" from
"she mentioned".

### Account

`iOSApp/Account/`, `Views/AccountView.swift`.

**The account is an identity, not a gate.** Sift has no server — the journal,
health log, and vault access are all on-device. So sign-in unlocks nothing:
every feature works signed out, **no code path checks for an account**, and
"Continue without an account" is a first-class path on the one-time welcome
screen. It exists to name the data and to be the seam a future sync feature
plugs into.

- **Sign in with Apple** is primary. Apple shares name/email only on the *first*
  authorization, so re-sign-ins carry forward the stored values instead of
  clobbering them. Revoked credentials are detected on launch.
- **Google sign-in** rides the same OAuth client as the Gmail/Calendar
  connections, with identity scopes. Disabled until the client ID lands, then
  lights up on its own. **No Google tokens are stored** — identity is one round
  trip reading the `id_token`.
- The JWT signature is **deliberately not verified**: verification protects a
  server session, and there isn't one. If a backend ever appears, revisit this.

### Assistant

`iOSApp/Assistant/`. Reads the journal through a single `JournalContext` choke
point — one place to audit AI access or add redaction.

Ships with `LocalQueryResponder`: deterministic, on-device, no model. Handles
category round-ups, weekly summaries, pending-queue questions, free-text search.
`AssistantResponder` is the protocol seam for a real model — the plan is Apple's
**Foundation Models** (iOS 26), on-device with guided generation that emits
structured Swift types, which is exactly what typed `ActionPayload`s need.

Like everything else: **the assistant proposes, it never executes.**

---

## Invariants — do not break these

1. **`propose()` has no side effects.** Ever.
2. **Nothing reaches an external service without user approval**, except what
   trust settings explicitly allow — and never for `isHighStakes` actions.
3. **Recipient addresses are never guessed.** Gmail proposals carry a *name*
   hint and leave `to` empty; Send stays disabled until a valid address is typed.
   Guessing is how you email the wrong person.
4. **Sift never writes workouts to HealthKit.** Read-only, empty share set.
5. **Never invent a number.** Unstated macros stay nil. Unparsed sets yield no
   exercises and keep the transcript. Bodyweight sets contribute zero volume,
   because Sift doesn't know what the user weighs.
6. **Never link to an Obsidian note that doesn't exist.**
7. **`SiftCore` must build for watchOS.** No `UIKit`, `Speech`, `EventKit`, or
   `HealthKit` in `Shared/`.

---

## Current state

**Builds and runs.** First compile succeeded after one fix (missing
`GENERATE_INFOPLIST_FILE` on the framework and test bundle). ~8,400 lines of
Swift, 71 files.

**Known open bug:** on the iOS simulator the app launches and renders the
Journal empty state, but **won't accept touches**. Two hypotheses, untested:

1. The launch `.task` in `SiftApp.swift` runs `refreshAppleCredentialState()`
   and `SpeechTranscriber.requestAuthorization()` sequentially before anything
   else; if speech authorization hangs on the simulator the main thread blocks.
2. The first-launch welcome sheet (`showingWelcome`) is presented but not
   visible, swallowing touches.

Fix (1) first — move the launch work off the critical path — since it's safe
regardless of the cause.

**Not yet configured** (see `Sift/SETUP.md`): `DEVELOPMENT_TEAM` is empty, and
`GoogleService.swift` still has a placeholder client ID, so the Google
connections and Google sign-in are inert. Everything else works without them.

### Testing on a simulator

There's no watch, so use the **compose button** in the top-right of Journal to
type a memo. It runs the identical pipeline as speech. Good test inputs:

| Type this | Should land in |
|---|---|
| `Remind me to call the dentist` | Review → Reminder proposal |
| `Squats 5×5 at 225, felt heavy on the last rep` | Health → Training, sets parsed |
| `Meeting with Sarah Thursday at 3` | Review → Calendar event |
| `Had a chicken salad, forty grams of protein` | Health → Meals, protein chip only |

`⌘U` runs the unit tests — categorizer, set extractor, Obsidian markdown
surgery, person-intent matcher, account parsing. None need signing or a device.

---

## Conventions

- **Comments explain *why*, not *what*.** The codebase is heavily commented
  where a decision is non-obvious or looks wrong without context (the 40 lb
  threshold, the unverified JWT, the empty `to` field). Match that. Don't add
  comments that restate the code.
- **Protocol seams for anything swappable**: `Categorizer`, `Transcriber`,
  `Destination`, `AssistantResponder`.
- Stores are `@MainActor ObservableObject`; services that destinations reach are
  `actor`s or singletons (`GoogleAuthStore.shared`, `ObsidianVault.shared`,
  `HealthLogStore.shared`, `HealthKitService.shared`).
- Swift 5.9. Value-type destinations reach `@MainActor` stores via explicit
  `await MainActor.run { … }` rather than relying on lenient checking.
- Longer design notes live in `Sift/obsidian/Sift/*.md` — an Obsidian vault of
  the project's own architecture docs. `Sift.md` is the index.

---

## Roadmap, roughly in order

1. Fix the simulator touch bug.
2. **Bevel-inspired redesign of the Health tab** — the next planned UI work.
3. Dark mode as a deliberate pass, not a system inversion.
4. Empty states for Journal and Review.
5. Background task assertion around the ingest pipeline so proposals finish
   generating during the watch hand-off wake.
6. A real model behind the Assistant (Foundation Models).
7. Meal macros → HealthKit as `HKCorrelation` once extraction is trustworthy.
8. Contacts (read-only) to offer — never auto-fill — email recipients.
