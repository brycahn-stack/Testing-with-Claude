---
tags: [project/sift, health, architecture]
created: 2026-07-31
---

# Health Tab

Part of [[Sift]]. Implemented in `Shared/Services/SetExtractor.swift`,
`iOSApp/Health/`, and `iOSApp/Views/HealthView.swift`.

Training and meals live in their own tab, apart from the life/business feed.
Body data reads as trends and sessions, not as a chronological stream of
thoughts, so mixing it into the journal made both worse.

## The finding that shaped this

**Apple Health cannot hold set data.** `HKWorkoutActivityType` covers ~80
activities — running, cycling, `traditionalStrengthTraining` — and a workout
carries duration, heart rate, and active energy. But there is no data type for
reps, sets, or weight lifted. No vocabulary for "barbell squat, 5×3, 225 lb".

You can attach custom metadata to a workout sample, but it's a private blob: the
Health app won't display it and no other app can read it. Which is why Strong,
Hevy, and every serious lifting app keep their own database and write only a
summary workout back for ring credit.

**The gap is the opportunity.** If HealthKit could hold set data, Sift would just
be a worse UI over it. It can't — so this tab holds something with nowhere else
to live.

## Three layers, three owners

| Layer | Owner | Why |
|---|---|---|
| Duration, heart rate, calories | **Apple Watch** | Already recorded it — Sift reads, never duplicates |
| Exercises, sets, reps, weight | **Sift** | Nowhere else can represent it |
| How it felt, what to change | **Your voice** | Nothing captures this today |

Linked by timestamp: `HealthKitService` finds the workout whose *end* is nearest
the memo (people record on the walk out of the gym) and attaches its numbers to
the session.

## Why Sift never writes a workout

Two independent reasons, either one sufficient:

1. HealthKit has no representation for what Sift knows.
2. The watch already logged the session. A written `HKWorkout` would be a
   duplicate **and** would credit invented calories to the Activity rings —
   corrupting the number the user cares most about.

So the entitlement requests read access and an empty share set. The
`NSHealthUpdateUsageDescription` string says so in as many words.

Meals are the mirror image: HealthKit *does* have a home for them
(`HKCorrelation` of type `.food`), but the numbers are much harder to hear. "A
chicken salad" carries no calorie count, and a guessed one is a number you'd go
on to make decisions with. So macros are recorded only when stated outright, and
the HealthKit write waits until extraction is good enough to trust.

## The extractor

`SetExtractor` is rules, not a model — a deliberate call. Gym language is a rigid
little grammar over a bounded vocabulary, so a handful of patterns covers most of
what anyone says between sets, and the useful half of this tab ships without
waiting on an LLM.

Handled today:

| Said | Parsed |
|---|---|
| "squats 5x5 at 225" | 5 sets × 5 @ 225 lb |
| "squat 225 for 5" | one set, 225 × 5 |
| "bench three sets of eight at 185" | 3 × 8 @ 185 |
| "deadlift 8, 8, 6 at 185" | three sets, shared weight |
| "225 for 5, 245 for 3, 265 for 1" | a ramping top set |
| "two twenty five" / "one thirty five" | 225 / 135 |
| "did 20 pushups" | 20 reps, bodyweight |
| "squat 100 kilos for 5" | kg respected |

Two disambiguation rules do most of the work:

- **The 40 lb threshold.** In "A x B", a leading number ≥ 40 is a weight
  ("225 x 5"); below it, a set count ("5 x 5"). An empty barbell is 45 lb, so
  nothing real sits near the line.
- **Adjacent-number merging** only fires when the middle token is a round ten,
  which is what stops "3 sets of 8" collapsing into 38.

**The contract when it fails: nothing invented, nothing lost.** An unparsed memo
yields no exercises, `WorkoutLog.isUnstructured` goes true, and the tab shows the
raw words. A wrong number in a training log is worse than no number, because
you'd train off it.

## Volume

The one number that means something across sessions. Computed in kilograms
internally so mixed units can't corrupt it, displayed in pounds.

Bodyweight sets contribute **zero** — Sift doesn't know what the user weighs and
won't guess a number they'd then track over time.

## Where a model earns its keep

- **Meal macros.** "A chicken salad" → calories and protein needs world
  knowledge, not patterns. This is the first feature that genuinely *requires* a
  model rather than merely benefiting from one.
- **Exercise names outside the vocabulary.** The list is ~25 movements; a model
  wouldn't need one.
- **Cross-session insight** — "your squat top set hasn't moved in six weeks."

## Not built yet

- Writing meals to HealthKit as `HKCorrelation` once macros are trustworthy.
- Per-exercise history and progression charts.
- Rest timers or anything live during a session — Sift is a capture tool, not a
  gym app.
