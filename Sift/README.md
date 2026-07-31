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
   - **Task** (no time) → **Reminders** (`EventKit`), or **Gmail** if it sounds
     like an email
   - **Schedule** / task with a time → **Calendar** event (`EventKit` or Google)
   - **Business Idea / Note** → **Obsidian** vault as Markdown, or a typed in-app
     log when no vault is connected
   - **Workout / Meal** → the **Health tab**, with sets and reps pulled out of
     the speech
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
│   ├── EntryPipeline.swift      #   transcribe → categorize → propose → store
│   ├── Connectivity/            #   Receives recordings
│   ├── Google/                  #   OAuth + Keychain for Gmail / Google Calendar
│   ├── Obsidian/                #   Vault folder access (security-scoped bookmark)
│   ├── Health/                  #   HealthKit reads + workout session matching
│   ├── Assistant/               #   JournalContext + the Assistant tab
│   ├── Routing/                 #   Destination protocol + all destinations
│   └── Views/                   #   Inbox, Review, Connections, preview sheets
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

> **Setting this up for the first time?** [`SETUP.md`](SETUP.md) walks through
> signing, HealthKit, and the Google OAuth client end to end — everything that
> has to happen outside the code, without needing to read any Swift.

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
control: *always ask*, or *auto when confident* (≥80%). Three things ignore the
setting and always wait for you: **sending email**, **inviting people to
events**, and **appending to a note you wrote**. "Approve all" skips those too.

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

## Obsidian

Obsidian is the odd one out: there's no API and no OAuth, because **a vault is
just a folder of Markdown**. You pick that folder once in Connections, iOS hands
back a security-scoped bookmark, and that bookmark *is* the connection. If the
vault syncs through iCloud Drive, notes written on the phone land on your Mac at
the next sync.

Because it's a folder and not an API, access is genuinely **two-way** — which
buys two things you can't get from a write-only integration:

- **Real wikilinks.** Sift reads the vault's note names and only links to pages
  that actually exist. It will never invent a `[[link]]` and leave an empty node
  in your graph.
- **Appending to notes you already keep.** Say *"remember that I work best in the
  mornings"* and it's added to your `About Me` note as a dated bullet under one
  configurable heading.

New notes carry frontmatter (tags, date, category) and the full transcript, so
they're searchable and graph-able the moment they arrive.

That append is **an edit to a file you wrote**, so it's the most guarded thing
in the app: the intent match is narrow and rejects anything that reads like a
task ("remember that I need to call the bank" is a to-do, not a fact); every
addition goes under a single heading so a year of them is one block you can
delete wholesale; and it's `isHighStakes`, meaning no trust level can
auto-approve it. The confirmation sheet reads the real file and shows your new
line highlighted in place.

The same machinery covers **the people in your vault**: *"Sarah mentioned she's
moving to Austin in the spring"* lands as a dated bullet in your `Sarah` note,
wherever it lives — or offers to create `People/Sarah.md` if there isn't one.
The matcher demands a telling verb and a capitalized name, and rejects pronouns
outright; "Sarah said the meeting moved to Thursday at 3" still becomes a
calendar proposal, not a line in Sarah's page.

Ideas and notes go to the vault when one is connected and fall back to the
in-app log when it isn't — the same way Google Calendar shadows Apple Calendar.

---

## Health

Training and meals get their own tab, apart from the life/business feed — body
data reads as sessions and trends, not as a stream of thoughts.

**Apple Health can't hold set data.** It models sessions and quantities: it knows
"45 minutes of strength training, 320 kcal" but has no data type for reps, sets,
or weight lifted. There's no vocabulary for "squat, 5×3, 225 lb". That's why
every serious lifting app keeps its own database — and it's exactly the gap this
tab fills.

So the split is three ways:

| Layer | Owner |
|---|---|
| Duration, heart rate, calories | **Your watch** — Sift reads it, never duplicates it |
| Exercises, sets, reps, weight | **Sift** — nowhere else can represent it |
| How it felt | **Your voice** |

Say *"squats, 5×5 at 225, felt heavy on the last rep"* and you get a structured
session, linked by timestamp to the workout your watch already recorded, with
your own words attached.

**Sift never writes a workout to Apple Health.** It would duplicate the watch's
session *and* credit invented calories to your Activity rings. The entitlement
asks for read access and an empty share set.

**The extractor is rules, not a model.** Gym language is a rigid little grammar
— "5x5 at 225", "three sets of eight", "225 for 5", "8, 8, 6 at 185", "two
twenty five" — so the useful half of this ships without waiting on an LLM. Two
rules do most of the work: in "A x B" a leading number ≥ 40 is a weight and below
that a set count (an empty bar is 45 lb), and spoken numbers only merge when the
middle word is a round ten, so "3 sets of 8" never becomes 38.

When it can't parse something, **nothing is invented and nothing is lost** — the
session keeps the raw memo and says so. A wrong number in a training log is worse
than no number, because you'd train off it.

Meals are the mirror image: HealthKit *does* have a home for them, but "a chicken
salad" carries no calorie count. Macros are recorded only when you state them
outright. Estimating them is the first thing here that genuinely needs a model.

> HealthKit requires the entitlement to be signed, which needs a paid Apple
> Developer account.

---

## Account (optional, by design)

Sift has no server — the journal, health log, and vault access all live on the
phone. So there is nothing for a login to gate, and Sift doesn't pretend
otherwise: **every feature works signed out**, and the first-launch screen's
"Continue without an account" is a first-class path, not a shamed footnote.

What signing in does: puts a name on your data, and gives a future sync/backup
feature its seam. What it doesn't do: anything else. No code path checks for an
account before doing work.

- **Sign in with Apple** is the primary — native, and working as soon as the
  development team is set. Apple shares your name and email only on first
  authorization; Sift stores them in the Keychain immediately.
- **Sign in with Google** rides the same OAuth client as the Gmail/Calendar
  connections (identity scopes are non-sensitive — no extra Google Cloud work).
  The button is disabled with an explanation until the client ID lands, then
  lights up on its own. Identity is one round trip: Sift reads the name and
  email from the `id_token` and stores no Google tokens at all.
- **Signing out** forgets the identity on this phone. It deletes nothing — the
  journal never belonged to the account.

The account screen also holds small per-person preferences, like the weight unit
assumed when a memo doesn't say one.

---

## Roadmap

The MVP captures, sorts, and files. Natural next steps, roughly in priority order:

- [ ] **Real model behind the Assistant** — Apple Foundation Models (iOS 26)
      replacing `LocalQueryResponder`, emitting typed `ActionPayload`s straight
      into the Review queue.
- [ ] **Background task assertion** — wrap the ingest pipeline in
      `beginBackgroundTask` so proposals finish generating during the watch
      hand-off wake instead of being truncated.
- [ ] **LLM categorizer** — an `LLMCategorizer: Categorizer` that extracts richer
      structure (task due dates, workout sets/reps, meal macros) with a
      confidence the router already knows how to gate on.
- [ ] **Meal macros to HealthKit** — write an `HKCorrelation` of type `.food`
      once extraction is trustworthy enough to be worth writing.
- [ ] **Per-exercise history** — progression charts off the set data now being
      collected.
- [ ] **Assistant reads the vault** — the vault is already readable, so answering
      from your notes as well as your journal is mostly a `JournalContext` change.
- [ ] **Obsidian daily notes / templates** for vaults that expect a house format.
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
