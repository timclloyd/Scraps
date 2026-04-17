# Data integrity & runtime performance audit

**Date:** 2026-04-17
**Scope:** Full-codebase audit focused on (1) data integrity and (2) runtime performance.
**Baseline commit:** `74fae9f` (main)

## Status at-a-glance

| # | ID | Severity | Title | Status |
|---|----|----------|-------|--------|
| 1 | C1 | Critical | `TextDocument` uses `DispatchQueue.main.sync` — deadlock risk | WIP in review (`fix/text-document-actor-safety`) |
| 2 | C2 | Critical | Scene-background saves don't wait — data loss on Cmd+Q / terminate | WIP in review (`fix/background-save-barrier`) |
| 3 | C3 | Critical | `loadScrapsInitial` Phase 2 assumes `scraps` untouched — stale inserts | Open |
| 4 | C4 | Critical | `deleteScrap` uses raw `FileManager.removeItem` — bypasses coordination | WIP in review (`fix/file-coordination`) |
| 5 | C5 | Critical | Directory create / enumerate / legacy move uncoordinated | WIP in review (`fix/file-coordination`) |
| 6 | H1 | High | Empty-scrap auto-delete races iCloud download | WIP in review (`fix/empty-scrap-download-race`) |
| 7 | H2 | High | `Calendar.current` captured once — TZ/DST drift vs UTC filenames | Open |
| 8 | H3 | High | `objectWillChange.send()` storm on every UIDocument state tick | Open |
| 9 | H4 | High | Search `computeMatches` O(N·M), no debounce | Open |
| 10 | H5 | High | `ForEach(Array(scraps.reversed()))` re-allocates every render | Open |
| 11 | H6 | High | Every archive card instantiates a full `UITextView` + regex compilation | Open |
| 12 | H7 | High | `TextHighlightManager` recompiles 7 regexes per instance | WIP in review (`fix/highlight-manager-perf`) |
| 13 | H8 | High | `textStorage.string` copies full document per keystroke | WIP in review (`fix/highlight-manager-perf`) |
| 14 | M1 | Medium | Double-dispatched scroll coalesces poorly at fast typing | Open |
| 15 | M2 | Medium | Per-coordinator `keyboardDidShow` observer duplicates shared tracker | Open |
| 16 | M3 | Medium | `UserDefaults.set` on every focus change | Open |
| 17 | M4 | Medium | `checkForUpdates` opens fresh `TextDocument` for every file | Open |
| 18 | M5 | Medium | No `NSMetadataQuery` — remote edits invisible until foreground | Open |
| 19 | M6 | Medium | Observer attach/cleanup ordering window in `replaceLoadedScraps` | Open |
| 20 | M7 | Medium | Phase-2 sort assumption fragile if filename scheme changes | Open |
| 21 | L1 | Low | Regex re-compile (dup of H7) | Addressed via H7 |
| 22 | L2 | Low | Silent legacy-move failures — no success/failure metric | Open |
| 23 | L3 | Low | Second-precision filename collision | Open |
| 24 | L4 | Low | No timestamp validation | Open |
| 25 | L5 | Low | Silent iCloud-unavailable handling | Open |
| 26 | L6 | Low | Single-retry scroll in `TextEditorView.scrollToRange` | Open |
| 27 | L7 | Low | `@unchecked Sendable` on `TextDocument` masks C1 | Addressed via C1 |

---

## Todo

- [ ] **C1** — Merge `fix/text-document-actor-safety`
- [ ] **C2** — Merge `fix/background-save-barrier`
- [ ] **C3** — After Phase 2 completes, diff against current `scraps` rather than `insert(at: 0)`
- [ ] **C4/C5** — Merge `fix/file-coordination`; add a lint rule or review checklist to keep raw `FileManager` calls on the iCloud container a forbidden pattern
- [ ] **H1** — Merge `fix/empty-scrap-download-race`
- [ ] **H2** — Read `Calendar.current` at each call site; align filename generation and same-day comparison on the same timezone (preferably local)
- [ ] **H3** — Only `objectWillChange.send()` on terminal state transitions (loaded, saved, conflict-resolved), not on progress ticks
- [ ] **H4** — Debounce search by ~150 ms; incrementally narrow prior results when the new query extends the old one
- [ ] **H5** — Store `scraps` newest-first (matches display order); drop the `reversed()` allocation
- [ ] **H6** — For non-focused scraps, use a read-only `AttributedString`/`Text` path instead of `UITextView`; reserve `UITextView` for the focused scrap only
- [ ] **H7/H8** — Merge `fix/highlight-manager-perf`
- [ ] **M1** — Coalesce `textViewDidChange` scroll via a cancellable `DispatchWorkItem`
- [ ] **M2** — Remove the per-coordinator `keyboardDidShow` observer; rely on the shared `KeyboardTracker` in `MainView`
- [ ] **M3** — Debounce focused-filename `UserDefaults.set`, or only persist on background
- [ ] **M4** — `checkForUpdates` should diff filenames against existing `scraps` before opening any new `TextDocument`
- [ ] **M5** — Add an `NSMetadataQuery` over the ubiquity container to pick up remote file additions while the app is foregrounded
- [ ] **M6** — In `replaceLoadedScraps`, close duplicate documents *before* attaching new observers
- [ ] **M7** — After Phase-2 insert, re-sort `scraps` by timestamp rather than assuming Phase-2 items are strictly older
- [ ] **L2** — Surface legacy-move failure via a user-visible signal or telemetry, not just `print`
- [ ] **L3** — Collision-proof filenames (append a short random suffix or monotonically-increasing counter on conflict)
- [ ] **L4** — Validate parsed timestamps fall within a sane range before trusting them
- [ ] **L5** — Handle iCloud-unavailable explicitly: surface a UI state rather than silently degrading
- [ ] **L6** — Replace the single 0.1 s retry in `scrollToRange` with a `didLayoutSubviews` observation
- [ ] **L7** — Once C1 lands, remove `@unchecked Sendable` and let the compiler prove safety

---

## Findings (full detail)

### CRITICAL

**C1. `TextDocument.contents(forType:)` uses `DispatchQueue.main.sync`** — [Cache/Managers/TextDocument.swift:12](../../Cache/Managers/TextDocument.swift). Fragile pattern known to deadlock with UIDocument's autosave machinery. Risk: hang on Cmd+Q / background save → data loss. Fix: maintain a nonisolated, lock-guarded text snapshot updated on every `updateText`; read it in `contents` without dispatch.

**C2. Scene-background saves don't wait for completion** — [Cache/Managers/DocumentManager.swift:258](../../Cache/Managers/DocumentManager.swift) + [Cache/App/ScrapsApp.swift:22](../../Cache/App/ScrapsApp.swift). `UIDocument.save` is async, no `beginBackgroundTask` barrier. On Cmd+Q the process can exit before writes land. Fix: wrap in `beginBackgroundTask` with a completion barrier across all scraps.

**C3. `loadScrapsInitial` Phase 2 `insert(at: 0)` assumes nothing else mutated `scraps`** — [Cache/Managers/DocumentManager.swift:138](../../Cache/Managers/DocumentManager.swift). If on-demand creation or deletion slips in, you get duplicate entries or stale `TextDocument`s. Fix: diff like `replaceLoadedScraps` does.

**C4. `deleteScrap` uses raw `FileManager.removeItem`, bypassing `NSFileCoordinator`** — [Cache/Managers/DocumentManager.swift:277](../../Cache/Managers/DocumentManager.swift). iCloud daemon can miss the delete; other devices may resurrect. Recurrence from 2025-11-13 review.

**C5. Directory create / enumerate / move uncoordinated** — [Cache/Managers/DocumentManager.swift:71,74,381](../../Cache/Managers/DocumentManager.swift). Stale listings and legacy-rename races with in-flight iCloud sync.

### HIGH

**H1. Empty-scrap auto-delete races iCloud download** — [Cache/Managers/DocumentManager.swift:34](../../Cache/Managers/DocumentManager.swift). `text == ""` before download completes → deletes a scrap that has remote content. Gate on `documentState` (no `.progressAvailable`).

**H2. `Calendar.current` captured once at init; timezone/DST drift** — [Cache/Managers/DocumentManager.swift:16](../../Cache/Managers/DocumentManager.swift). Filenames are UTC ([Cache/Models/Scrap.swift:47](../../Cache/Models/Scrap.swift)) but same-day check is local — inconsistent near midnight.

**H3. `objectWillChange.send()` fires on every UIDocument state change** — [Cache/Managers/DocumentManager.swift:495](../../Cache/Managers/DocumentManager.swift). Progress ticks during iCloud download storm the entire MainView + ArchiveList + search re-render.

**H4. Search `computeMatches` is O(N·M) per keystroke, no debounce** — [Cache/Views/MainView.swift:143](../../Cache/Views/MainView.swift).

**H5. `ForEach(Array(scraps.reversed()))` reallocates every render** — [Cache/Views/ArchiveListView.swift:22](../../Cache/Views/ArchiveListView.swift). Consider storing newest-first.

**H6. Every archive card instantiates a full `UITextView` + `NSLayoutManager` + regex compilation** — [Cache/Views/TextEditorView.swift:35](../../Cache/Views/TextEditorView.swift) via ScrapCardView. Scroll hitches on long scraps. Use rendered `AttributedString` for non-focused scraps.

**H7. `TextHighlightManager` re-compiles 7 `NSRegularExpression`s per instance** — [Cache/Managers/TextHighlightManager.swift:29](../../Cache/Managers/TextHighlightManager.swift). Hoist to `static let`.

**H8. `textStorage.string` copies full document per keystroke** — [Cache/Managers/TextHighlightManager.swift:90](../../Cache/Managers/TextHighlightManager.swift). 50k-char scrap → 50k copy per key. Use `mutableString`.

### MEDIUM

- **M1.** Double-dispatched scroll coalesces poorly at fast typing — [Cache/Views/TextEditorView.swift:156](../../Cache/Views/TextEditorView.swift).
- **M2.** Per-coordinator `keyboardDidShow` observer duplicates shared `KeyboardTracker` — [Cache/Views/TextEditorView.swift:135](../../Cache/Views/TextEditorView.swift).
- **M3.** `UserDefaults.set` on every focus change — [Cache/Views/ScrapView.swift:37](../../Cache/Views/ScrapView.swift).
- **M4.** `checkForUpdates` opens fresh `TextDocument` for every file then closes duplicates — [Cache/Managers/DocumentManager.swift:145](../../Cache/Managers/DocumentManager.swift). Diff by filename first.
- **M5.** No `NSMetadataQuery` / `NSFilePresenter` — remote edits invisible until backgrounding.
- **M6.** Observer attach/cleanup ordering window in `replaceLoadedScraps` — [Cache/Managers/DocumentManager.swift:298](../../Cache/Managers/DocumentManager.swift).
- **M7.** Phase-2 sort assumption fragile if filename scheme changes — [Cache/Managers/DocumentManager.swift:138](../../Cache/Managers/DocumentManager.swift).

### LOW

Regex re-compile (L1, dup of H7); silent legacy-move failures (L2); second-precision filename collisions (L3); no timestamp validation (L4); no iCloud-unavailable handling (L5); single-retry scroll ([Cache/Views/TextEditorView.swift:211](../../Cache/Views/TextEditorView.swift)) (L6); `@unchecked Sendable` masks C1 (L7).

---

## Hot paths

1. **Keystroke**: full-string copy (H8) + UserDefaults write (M3) + double-dispatch (M1).
2. **Foreground**: re-opens every doc (M4) + `objectWillChange` storm (H3) + empty-delete race (H1).
3. **Archive scroll**: UITextView + regex rebuild per cell (H6, H7).
4. **Search**: O(N·M) no debounce (H4).

## Recurring (since 2025-11-13 review)

- **Still unfixed** at baseline: NSFileCoordinator gaps (C4, C5 — now on `fix/file-coordination`), filename collision (L3), timestamp validation (L4), iCloud unavailability (L5).
- **Partially addressed**: observer race (refactored to dictionary keyed by `ObjectIdentifier`) — introduces new ordering hazard M6.
- **New this review**: C1, C2, H1, H3, H8.

**Systematic recommendation**: add a thin `CoordinatedFileOps` choke-point (started informally by the helpers in `fix/file-coordination`) and make direct `FileManager` usage on `documentsDirectoryURL` a forbidden pattern.
