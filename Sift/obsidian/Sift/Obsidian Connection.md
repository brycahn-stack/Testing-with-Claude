---
tags: [project/sift, integrations, obsidian]
created: 2026-07-30
---

# Obsidian Connection

Part of [[Sift]]. Implemented in `iOSApp/Obsidian/` and
`iOSApp/Routing/ObsidianDestinations.swift`.

## Why this one is different

Gmail and Google Calendar are APIs behind OAuth. Obsidian isn't — **a vault is
just a folder of Markdown on disk**. So there's no OAuth, no token, no scope
string. The user picks the folder once in the Files app, iOS hands back a
**security-scoped bookmark**, and that bookmark *is* the connection.

Two consequences:

- **Access is genuinely two-way.** Sift can read the vault, not just write to it.
  That's what makes `[[wikilinks]]` resolve to pages that really exist, and it's
  what lets Sift append a fact to a note you already keep.
- **The folder is the boundary.** Sift can reach everything inside the vault and
  nothing outside it. That's a bigger grant than "Gmail can't read your inbox" —
  and worth saying plainly in Connections, which is what the capability line does.

If the vault lives in iCloud Drive (the usual setup for people who also run
Obsidian on a Mac), a note written on the phone shows up on the desktop at the
next sync. Sift never talks to the Mac directly; iCloud does the moving.

## Destinations

| Destination | Handles | Mode |
|---|---|---|
| `ObsidianDestination` | Note, Business Idea | Creates a new `.md` file |
| `ObsidianProfileDestination` | "Remember that I…" | Appends to your profile note |

`ObsidianDestination` sits ahead of `LogDestination.idea` and `NoteDestination`
in the router and returns `nil` when no vault is connected — the same shadowing
trick the Google destinations use, so ideas go to the vault if you keep one and
to the in-app log if you don't.

`ObsidianProfileDestination` sits **first** in the whole router, because
"remember that I prefer mornings" would otherwise be read as a task and land in
Reminders.

## What a new note looks like

```markdown
---
tags: [sift, sift/idea]
category: Business Idea
created: 2026-07-30
source: sift
---

# Voice journal that files itself

Full transcript of the memo.

## Related

- [[Product Strategy]]
```

Frontmatter keys render in sorted order, so re-running the same memo produces
identical bytes. The rendering lives on `MarkdownNoteDraft` itself, which means
the confirmation sheet previews the *literal file* — there's no second code path
that could disagree with what gets written.

## The profile note ("About Me")

The feature that motivated the connector: say *"remember that I work best in the
mornings"* and it gets appended to the note you already keep about yourself.

```markdown
## From Sift

- I work best in the mornings — *2026-07-30*
```

This is **the only place Sift edits a file the user wrote**, so it carries the
most guard rails of anything in the app:

1. **Narrow intent.** `ObsidianProfileIntent` takes an explicit lead-in
   ("remember that I…", "for the record, I…") or an unmistakably stative opener
   ("I prefer…"), then *rejects* the result if the predicate reads like an action
   — "remember that I need to call the bank" is a task, not a fact. Missing a
   fact costs nothing; it becomes an ordinary note. Mistaking a to-do for a fact
   would quietly corrupt someone's own writing.
2. **One heading.** Everything lands under a single configurable heading, so a
   year of additions is still one block you can review, move, or delete wholesale.
3. **Always asks.** `MarkdownNoteDraft.Mode.appendToNote` makes the action
   `isHighStakes`, which no trust level can override. Creating a note is additive
   and reversible; editing one is not.
4. **Shows the real file.** The confirmation sheet reads the actual note and
   renders its tail with the new line highlighted in place.

If the profile note doesn't exist yet, the proposal switches to creating it, with
the same bullet as its body.

## Wikilinks

`ObsidianLinker` only links to notes it has **seen in the index**. A link to a
page you don't have creates an empty node in your graph — exactly the sort of
quiet mess that makes people stop trusting an integration. Matching is on word
boundaries (so "cats" doesn't match inside "catalog"), longest name first, and
skips names common enough to hit by accident (`Ideas`, `Notes`, `Work`, …).

## Implementation notes

- **`NSFileCoordinator` on every read and write.** A synced folder can be written
  by the sync daemon mid-edit; uncoordinated writes are how you lose a paragraph.
  The append is a read-modify-write inside one coordinated block.
- **Never overwrites.** A clashing filename gets ` 2`, ` 3`, … the way a Finder
  copy would.
- **Stale bookmarks self-heal.** If the vault is moved or renamed, the resolved
  bookmark is refreshed in place rather than making the user re-pick a folder
  that's still perfectly reachable.
- **The index is cached** and invalidated on write, so proposing doesn't re-walk
  the vault for every memo. `.obsidian` and `.trash` are skipped.

## Settings (Connections tab)

| Setting | Default | What it does |
|---|---|---|
| New notes in | `Sift` | Vault-relative folder; empty writes to the root |
| Link to existing notes | on | Adds `[[wikilinks]]` for vault notes a memo mentions |
| Remember facts about me | on | Enables the profile append entirely |
| Note | `About Me` | Which note facts go into |
| Under heading | `From Sift` | Which heading they land under |

## Not built yet

- **Reading the vault for the [[Assistant and Review Queue|Assistant]].** The
  vault is already readable, so letting the assistant answer from your notes as
  well as your journal is mostly a `JournalContext` change.
- **Daily-note append** — many vaults key everything off a daily note; Sift
  currently writes standalone files.
- **Templater / template support** for people whose vaults expect a house format.
