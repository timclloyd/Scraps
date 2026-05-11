# Plan: Plain-Text Sync Conflicts — preserve concurrent edits without abandoning markdown files

## Context

Scraps stores each note as a plain text file in the user's iCloud container. That is a core product property: the archive is readable outside the app, portable, and not dependent on a private database or sync engine.

The current conflict strategy is too lossy for that model. When Mac and iPhone edit the same scrap before iCloud has synced the latest version, each device can save a complete but stale version of the same file. iCloud then surfaces the competing file versions through `UIDocument` / `NSFileVersion`, and Scraps resolves by keeping iCloud's current version and removing the rest.

That is simple, but it means a valid edit from one device can disappear after the other device wins the conflict.

This PRD proposes a conservative conflict-handling layer that keeps the on-disk truth as plain text while changing the failure mode from **silent loss** to **merged text or inline preserved conflict sections**.

## Problem

Repro shape:

1. Mac and iPhone both have scrap version `A`.
2. Mac edits the scrap to `A + M` and saves.
3. Before iPhone receives `A + M`, iPhone edits its stale local copy to `A + P` and saves.
4. iCloud has two divergent descendants of `A`.
5. Scraps' current conflict handler removes non-current versions.
6. If iPhone's version becomes current, Mac-only text `M` disappears when Mac reloads.

The important detail: Scraps saves whole text files. Without app-level merge semantics, any stale save is a whole-document overwrite.

## Goals

- Keep every scrap as a normal plain text / markdown-readable file.
- Never silently discard conflict versions.
- Resolve simple concurrent edits automatically when safe.
- Preserve ambiguous conflicts as plain-text sections inside the affected scrap so the data remains visible without creating duplicate archive scraps.
- Avoid moving the primary data model to CloudKit, Core Data, a database, or a CRDT.
- Keep the first implementation small enough to ship and verify on real devices.

## Non-goals

- No live collaborative editing.
- No CRDT or operational-transform engine.
- No app-private binary document format.
- No server-side merge service.
- No attempt to perfectly understand markdown structure in v1.
- No automatic rewriting that can hide or reinterpret the user's text.

## Current implementation notes

Relevant files:

- `Cache/Managers/TextDocument.swift` — `UIDocument` subclass. `updateText(_:)` marks the entire document dirty.
- `Cache/Managers/DocumentSaveCoordinator.swift` — saves each scrap with `.forOverwriting`.
- `Cache/Managers/DocumentManager.swift` — observes `UIDocument.stateChangedNotification`; when `.inConflict`, removes non-current versions through `NSFileVersion.removeOtherVersionsOfItem(at:)`.
- `Cache/Views/ScrapView.swift` — typed editor path calls `DocumentManager.textDidChange(...)`, which saves immediately.
- `Cache/Views/ScrapPreviewView.swift` — archive strikethrough path currently calls `document.updateText(updatedText)` directly and should be moved through the same save path.

The bug is not missing file coordination. `UIDocument` gives us coordinated reads/writes and conflict detection. The missing piece is semantic conflict preservation.

## Desired behavior

### Clean conflict

If two versions changed different parts of the text and a line-based merge can combine them with high confidence:

1. Merge into the primary scrap file.
2. Save the merged text.
3. Mark all conflict versions resolved.
4. Remove old conflict versions only after the merged save succeeds.

### Ambiguous conflict

If both versions changed the same nearby lines, or the merge cannot confidently prove that no text will be lost:

1. Keep one version as the primary scrap file.
2. Append every other conflicting version to that scrap as a visible plain-text preservation section.
3. Avoid visible metadata beyond the source device; repeated iCloud conflict notifications should not append the same preserved content again.
4. Mark iCloud conflict versions resolved only after the updated scrap has been saved successfully.

Example preserved section:

```markdown
---
🔀 Sync conflict preserved from Tim's iPhone

<conflicting text here>
---
```

## Merge strategy

### v1: conservative line merge

Use a line-oriented merge with a bias toward preserving content:

1. Read the current version and all unresolved conflict versions as UTF-8 text.
2. Choose a base if available.
   - First preference: `lastKnownSavedText` tracked by the app for this document.
   - Fallback: no base; run two-way preservation logic.
3. Attempt a three-way line merge when base exists.
4. If a hunk is clean, merge it.
5. If a hunk overlaps ambiguously, stop auto-merge and fall back to inline preserved conflict sections.

Do not ship a clever merge that can drop lines. The rule should be: if uncertain, preserve the conflicting version inline.

### Base tracking

Add lightweight per-document metadata in memory:

- `lastKnownSavedText`: updated after successful open and successful save.
- `hasUnsavedLocalChanges`: true after local mutation, false after save completion for the same text.
- `lastLocalEditDate`: useful for logging and tie-breaks.

This does not need to be persisted for v1. It improves active-session conflict merges. If the app relaunches during a conflict, fallback preservation still prevents loss.

### Future refinement

If we later want better markdown-aware merges:

- Treat paragraphs or list items as blocks.
- Use stable block IDs only if we are willing to add hidden markers, which is probably against the plain-text aesthetic.
- Consider diff-match-patch style character merges for single-paragraph concurrent appends.

## Architecture

### New files

- `Cache/Managers/ScrapConflictResolver.swift`
  - Reads `NSFileVersion` conflict versions.
  - Produces a `ConflictResolutionPlan`.
  - Applies either merged text or inline preserved conflict sections.

- `Cache/Managers/TextMerge.swift`
  - Small deterministic text merge helper.
  - No iCloud or UIKit dependencies.
  - Unit-testable with plain strings.

- `Cache/Models/ScrapConflictVersion.swift`
  - Metadata wrapper around a version: source name if available, modification date, text, file version URL.

### Changes to existing files

- `DocumentManager.handleDocumentStateChanged(_:)`
  - Replace immediate last-writer-wins cleanup with `ScrapConflictResolver`.
  - Only mark conflict versions resolved after merged text or inline preservation is durable.

- `DocumentSaveCoordinator`
  - Report successful save completion back to `TextDocument` / metadata tracking.
  - Optionally serialize saves per document so older async save completions cannot update `lastKnownSavedText` after a newer edit.

- `TextDocument`
  - Track save/open baseline text.
  - Consider adding a monotonically increasing local revision counter.

- `ScrapPreviewView`
  - Route strikethrough mutations through `DocumentManager.textDidChange(for:newText:)` or a new central mutation API so those edits save immediately.

- `ScrapFileStore`
  - No conflict-copy file writer required for v1; preservation happens through the normal scrap save path.

## UX

v1 can be deliberately quiet:

- If a conflict auto-merges cleanly, no UI is required.
- If conflict sections are appended, keep the signal in the scrap text itself; no extra archive marker is required.

```text
Sync conflict preserved
Scraps kept both versions in the affected note.
```

No modal interruption during typing. The affected archive scrap should visibly contain the preserved section.

Future UI could add a small conflict banner on the preserved scrap with actions:

- Keep preserved text
- Delete preserved section
- Open original

Those actions are not required for v1.

## Logging and diagnostics

Add temporary structured logs around conflict handling:

- filename
- current version modification date
- conflict version count
- conflict version modification dates
- text byte counts
- selected resolution path: clean merge, inline preservation, error
- save success/failure for merged file or preserved section

This logging is important for real-device testing because iCloud timing is nondeterministic.

## Failure handling

- If reading a conflict version fails, do not resolve it. Leave iCloud's conflict state intact and log the error.
- If writing a merged file fails, do not remove other versions.
- If writing the preserved section fails, do not mark versions resolved.
- If merge output is identical to the current document, it is still safe to resolve only after confirming every conflict version's text is represented in the chosen output or already has a preserved section.

The invariant: resolving an iCloud conflict is the final step, never the first step.

## Phasing

### v1 — Stop silent loss

- Add `ScrapConflictResolver`.
- On conflict, read all versions.
- Attempt conservative line merge.
- Fall back to inline preserved conflict sections.
- Mark versions resolved only after preservation succeeds.
- Route archive strikethrough edits through the normal save path.
- Add focused unit tests for merge and conflict-planning logic.

### v1.1 — Better active-session merges

- Track `lastKnownSavedText`, dirty state, and local revision counters per document.
- Use that baseline for true three-way merges during active concurrent editing.
- Serialize per-document saves or ignore stale save completions by revision number.

### v2 — Conflict UX polish

- Add a small conflict-preserved banner on scraps containing preserved sections.
- Provide quick actions to keep/delete/open preserved sections.
- Add a debug view or exportable conflict log for field reports.

## Verification

1. Unit: base `A`, Mac `A + M`, phone `A + P` on different lines. Resolver returns merged text containing both `M` and `P`.
2. Unit: both versions edit the same line differently. Resolver refuses auto-merge and plans inline preservation.
3. Unit: identical conflict version. Resolver does not create duplicate content.
4. Unit: invalid UTF-8 conflict content. Resolver leaves conflict unresolved and reports failure.
5. Unit: duplicate conflict content is not appended twice even if metadata differs.
6. Integration: archive strikethrough calls the central mutation path and triggers a save.
7. Device: Mac edits a scrap, iPhone edits stale same scrap before sync, both versions are preserved after reload.
8. Device: repeat the same test with one device offline, then bring it online.
9. Device: force-quit during conflict resolution. Confirm either the conflict remains unresolved or the preserved section exists; no version is silently deleted.
10. Device: conflict auto-merge path creates a readable plain-text primary scrap.
11. Device: conflict fallback path creates a visible readable plain-text section in the affected archive scrap.
12. Regression: ordinary single-device typing still saves immediately and syncs normally.

## Open questions

1. Should preserved sections be visually summarized outside the raw text? Recommendation: no for now; keep the scrap text as the visible source of truth.
2. Should the primary scrap get a header when an auto-merge occurs? Recommendation: no for v1; avoid adding app metadata to normal notes.
3. Can `NSFileVersion` reliably expose localized device names? If not, use generic labels like `version-1` plus modification timestamps.
4. How aggressive should clean auto-merge be? Recommendation: conservative. Fall back to inline preservation whenever a merge hunk overlaps.
5. Should we keep conflict versions in iCloud after writing preserved sections? Recommendation: no; once preservation is durable, mark resolved to avoid persistent conflict state and quota buildup.
