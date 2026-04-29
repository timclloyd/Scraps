# Complexity Review — 2026-04-19

Short answer: **yes, somewhat — but much of the complexity is genuine, not accidental**. The app is ~2700 lines across 17 files, which is small. But the distribution is skewed: `Cache/Managers/DocumentManager.swift` is 828 lines with 34 methods, and `Cache/Views/TextEditorView.swift` is 421. Those two files carry most of the weight.

## What's load-bearing (leave it)

iCloud + UIDocument is fundamentally hard. NSFileCoordinator, conflict versions, ScenePhase for Cmd+Q, ubiquity probing, background-save barriers — none of that is over-engineering, it's the cost of doing multi-device sync correctly. `Documentation/icloud-sync-best-practices.md` exists for a reason.

## What looks like accretion (worth refactoring)

### 1. `DocumentManager` is a god object

It owns: iCloud probing, legacy file migration, scrap CRUD, conflict resolution, focus state, document-observer lifecycle, and background-save coordination. That's four or five responsibilities.

Splitting into something like `ScrapStore` + `FocusCoordinator` + `SyncHealthMonitor` would make each piece independently testable and kill a lot of flag-juggling.

### 2. Dual identity (`focusedScrapID` + `focusedScrapFilename`)

Both are tracked because scraps get deleted and re-created, breaking ID identity. The filename is already a stable natural key.

Collapsing to filename-only would eliminate a whole class of "ID stale after re-create" bugs by construction. **High-value simplification.**

### 3. Implicit state machine

`isInitialLoad`, `hasBackgrounded`, `isReady`, `iCloudAvailable` compose into a state machine that isn't spelled out. An explicit `enum State { probing, loading, ready, unavailable }` would remove "what if both are true?" cases.

### 4. Defensive comments are a canary

Phrases like "Load-bearing invariant", "Phase 2 dedup", "settle filter", "Race window close" show up repeatedly. Each landed via a real bug fix — but they're holding the system together through discipline rather than structure.

When a comment is load-bearing for correctness, the data model usually needs tightening. Items 2 and 3 above would make ~half of these comments unnecessary.

### 5. `TextEditorView` does too many jobs

Shake gesture + tap-to-focus + keyboard tracking + scroll-to-range (with retry) + caret-at-tap-location + line strikethrough preview + first-responder acquisition.

`KeyboardTracker` already exists in `MainView` as its own type — same pattern applied to shake and scroll behaviours would shrink this file meaningfully.

## Prioritisation

If picking one thing: **collapse the id/filename duality (item 2)**. It's the smallest structural change with the biggest ripple — several race windows and defensive guards fall out as dead code once filename is the sole identity.

Items 1 and 3 are bigger but more mechanical.

## Verdict

The app isn't *bloated* — it's a tight product. But the internals have accumulated the classic "each fix adds a flag" pattern, and the H3/C3/H6/L3/L5 fix series on top of main is a symptom. A round of simplification before the next feature would pay off.
