---
tags: [project/sift, ml, nlp]
created: 2026-07-30
---

# Categorization Engine

Part of [[Sift]]. Implemented in `Shared/Services/Categorizer.swift`.

The job: turn free-form speech into one of six buckets, with a confidence score
and structured hints (dates), so [[Routing and Integrations]] knows where to send it.

## The categories

| Category | Example memo | Routes to |
|---|---|---|
| Business Idea | "app idea — a SaaS for founders" | Idea log |
| Task | "remind me to call the dentist" | Reminders |
| Schedule | "meeting tomorrow at 3" | Calendar |
| Workout | "five sets of squats, two mile run" | Workout log |
| Meal | "lunch was a chicken salad, 40g protein" | Meal log |
| Note | "the sky looked purple tonight" | Kept as note |

## How it works (`KeywordCategorizer`)

Fully on-device, deterministic, explainable:

1. **Signal phrases.** Each category has a set of trigger phrases. Multi-word
   phrases score higher (2.0) than single words (1.0) because they're less
   ambiguous.
2. **Date detection.** `NSDataDetector` pulls out any dates/times. A concrete time
   is a strong "put this on the calendar" signal (+2.5 to Schedule).
3. **Scoring.** The highest-scoring category wins. A task that names a specific
   time is promoted from Task → Schedule.
4. **Confidence.** Blends *dominance* (how far ahead the winner was) with
   *magnitude* (did it score much at all). Below **0.5** the entry is flagged for
   manual review instead of auto-routed.

## Why keyword-based first

- **Explainable** — you can see exactly which phrases fired.
- **Free + offline + private** — no API, no network, no data leaves the device.
- **An honest fallback** even once a smarter model exists.

## The upgrade path

`Categorizer` is a protocol:

```swift
protocol Categorizer {
    func categorize(_ text: String) -> CategorizationResult
}
```

So an `LLMCategorizer` (on-device or API) can replace the keyword one without
touching routing, storage, or UI — it just needs to return the same
`CategorizationResult`. See [[Roadmap]]. Related: the [[iOS Integration Options]]
determine what structured fields are worth extracting (due dates, sets/reps,
macros).
