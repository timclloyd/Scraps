# Plan: Open-Loop Markers — surfacing unresolved intentions on the minimap

## Context

Plain scraps capture plenty of fleeting commitments — todos, questions, "want to try X", "remember to Y" — that never get explicitly resolved. The user has no ambient way to see which of their past captures are still *unfinished*. Search only finds things you already remember you wrote.

This PRD proposes **open-loop markers** layered onto the valence minimap (`2026-04-PRD-valence-minimap.md`): small visual indicators on the minimap strip showing scraps that contain at least one unresolved intention. Tapping a marker jumps to the specific line, not just the scrap.

The feature is designed so that **most of its value is available without an LLM**. Syntactic detection + the app's existing strikethrough gesture carry ~80% of the useful cases. A later, optional LLM phase adds cross-scrap resolution detection.

Sibling docs:
- Valence minimap (`2026-04-PRD-valence-minimap.md`) — the visual surface this feature layers onto. Required first.
- Patterns (`2026-04-PRD-patterns.md`) — earlier exploration of LLM-surfaced patterns; retained as reference, this PRD is the descendant that narrows Patterns' best idea (dormant threads) into a single ambient feature.

## Scope

**In scope:**

- Per-scrap detection of lines that look like unresolved intentions.
- Strikethrough-aware: struck lines are authoritatively resolved, regardless of detector match.
- Markers on the minimap for scraps with ≥1 open loop.
- Tap on a marker → scroll to the scrap and highlight the specific open-loop line(s).
- Optional LLM-assisted resolution detection (v2) — fading markers on loops that appear to have been addressed in later scraps.

**Not in scope:**

- No automatic text rewriting. The detector reads; the user owns the text.
- No "assignments", due dates, priorities, or reminders. This isn't a todo app.
- No notifications or push. Stays passive, like the rest of the app.
- No cross-scrap *aggregation* of loops (e.g. "you have 47 open loops total") — that risks becoming a guilt mechanic. Markers are navigational, not a score.

## Detection heuristics (v1 — no LLM)

A line is a candidate open loop if it matches any of:

1. **Todo-list context** — appears within a block headed by the word `todo` (case-insensitive), as a line item.
2. **Imperative opening** — line starts with a common imperative verb: `buy`, `call`, `clean`, `cut`, `email`, `finish`, `fix`, `pack`, `reply`, `send`, `tidy`, `wash`, `write`, etc. A curated list, not exhaustive — quality over recall.
3. **Intention markers** — line contains a first-person intention phrase: `i will`, `i want to`, `i'm going to`, `i need to`, `i should`, `remember to`, `note to self`, `next time`.
4. **Captured questions** — line ends with `?` and is not a heading (see below).

**Excluded (not a loop):**

- Lines that are already struck through (any strikethrough marker the app supports).
- Lines inside a known markdown-style heading.
- Very short fragments (<3 meaningful words) that are likely labels, not actions.
- Lines containing a URL and nothing else — that's a reading pointer, not a commitment, even if it looks imperative.

**Per-scrap output:** a set of `(lineRange: NSRange, matchedRule: Rule)` tuples. Empty set → no marker.

## Resolution states (v1)

Each open-loop candidate is in one of three states:

- **Open** — detected, not struck, no resolution signal.
- **Done** — the line itself is struck through. Authoritative. Strikethrough is the user's explicit "done" gesture and overrides everything else.
- **Stale** (optional, v1.1) — detected in a scrap older than N days (e.g. 60) with no strikethrough. Rendered differently (e.g. desaturated marker) to distinguish from fresh loops.

Only Open (and optionally Stale) scraps get markers. Done loops are silent — the user has already closed them.

## UX / visual integration

**Marker appearance on the minimap:**

- A small inset notch or tick on the left side of the valence strip — leaves the valence colour band untouched to the right.
- One marker per scrap regardless of how many loops it contains (the minimap is too thin for counts). Tap reveals all loops in the scrap.
- Marker colour: neutral/high-contrast against the strip background, not a valence colour — this is meta-information, not mood.

**Tap behaviour:**

- Tap on a marker: scroll the archive to the scrap (same animation as search / minimap taps), then use `activeSearchRange` to highlight the first open-loop line within the scrap (reuse the search-match highlight path). If the scrap has multiple loops, subsequent taps on the same marker cycle through them (reuse the next/prev match mechanism).

**Does not replace the valence-colour row:** markers are additive — a scrap can have both a valence composition band and a loop marker.

**Global toggle:** a subtle control (perhaps a long-press on the minimap, or a toolbar item in the archive view) to hide/show markers entirely. Some users may find them distracting; it's an ambient feature, not a mandatory one.

## Architecture

### New files

- `Cache/Managers/OpenLoopIndex.swift` — computes and caches per-scrap open-loop candidates. Listens for document text changes and recomputes only the affected scrap. Publishes `[ScrapID: [OpenLoop]]`.
- `Cache/Models/OpenLoop.swift` — `struct OpenLoop { scrapID, lineRange: NSRange, matchedRule, state: State }`.

### Changes to existing files

- `Cache/Views/ArchiveMinimapView.swift` — overlay marker rendering on top of the existing valence-band rendering.
- `Cache/Managers/TextHighlightManager.swift` — detection regexes live here alongside valence and utility keyword patterns, for consistency.

### Strikethrough detection

The app already supports strikethrough via a line-level gesture (`EnhancedTextView`'s strikethroughPreviewLayer + whatever marker gets written into the text). `OpenLoopIndex` reads the scrap's attributed text / serialised markers and excludes struck lines from the candidate set. Need to confirm how strikethroughs are persisted in the scrap text (visible `~~…~~` markers vs attributed-string metadata) — that determines whether the detector reads plain text or attributed text.

## Phasing

**v1 — Heuristic markers. No LLM.**
- `OpenLoopIndex` with the heuristic ruleset above.
- Minimap marker rendering + tap-to-jump-to-line.
- Strikethrough-aware exclusion.
- Ships on all iOS versions the app supports — no OS version floor.

**v1.1 polish:**
- Stale-state desaturation for old unresolved loops.
- Per-loop cycle tapping (next/prev within a scrap).
- Global toggle.

**v2 — LLM-assisted resolution detection. iOS 26+.**
- For each open loop, a scoped `FoundationModels` prompt asks: "Does any of these N later scrap excerpts address this intention?" Model returns yes/no + cited excerpt.
- On yes, the loop's state transitions to **Addressed**; its marker fades out or disappears.
- Strictly enhances v1 — v1 markers remain accurate without it. No regression on older OSes.
- `LanguageModelClient` wrapper (originally scoped in the Patterns PRD) lives here, narrowly scoped to this one question. Simpler than the earlier multi-detector infrastructure.

**v2 trust contract:**
- Same invariants as the Patterns PRD: no network, no text mutation, structured output validated against input IDs, dismissed resolutions don't reappear.
- Narrower surface: the model answers exactly one yes/no-with-citation question per open loop. Much less prompt-engineering risk than themes / sentiment / connections.

## Reuse from existing code

- `ScrollViewReader` proxy + animated `scrollTo` path from search navigation.
- `activeSearchRange` + `activeMatchScrapID` in `ArchiveListView` — the exact same machinery used for search match highlighting. An open-loop tap is essentially a search-match jump with a different source.
- `TextHighlightManager` regex-compilation + per-line processing pipeline.
- `Theme.navigationIn` / `navigationOut` for any animated transitions.

## Open questions / assumptions

1. **Strikethrough representation.** Is it stored as inline `~~text~~` in the serialised scrap file, as an attributed-string attribute on the live document, or both? The detector's implementation depends on this. Needs a quick code read before building.
2. **Imperative verb list.** A curated list will miss verbs the user uses that aren't in it. Fine for v1 — ship with ~30 common ones and extend based on real usage. A full NLP verb detector is overkill.
3. **False-positive tolerance.** Markers are *always visible* (unlike a review tab), so false positives feel worse than false negatives. Ship with conservative heuristics, high precision / lower recall. Better to miss than to nag.
4. **Locale.** All heuristics assume English. Non-English text won't get loop markers. Fine for v1; platform i18n is a bigger question for the whole app.
5. **"fuck" as an imperative.** The imperative-verb rule should exclude expletives and casual fragments, otherwise `"fuck this"` becomes an open loop. Curation over regex generality.
6. **Marker density.** On long archives, visually verify marker density is readable at 4–6pt row heights. If markers cluster too tightly, consider collapsing adjacent same-scrap markers into a single indicator with a "cluster" variant.

## Verification

**v1:**

1. Build + run on a corpus with known open loops. Confirm markers appear on the expected scraps and nowhere else.
2. Strike through a previously-detected open loop. Confirm its marker disappears on next re-index (should happen immediately on text change).
3. Tap a marker. Confirm the archive scrolls to the scrap and the correct line is highlighted via the search-match path.
4. Tap the same marker repeatedly on a multi-loop scrap. Confirm it cycles through the loops.
5. Toggle markers off via the global control. Confirm the minimap returns to valence-only mode without regression.
6. Feed the detector known-false cases (e.g. URLs, headings, struck lines, past-tense non-intentions). Confirm no markers generated.
7. Performance: 1000-scrap corpus full re-index should be <100ms; incremental re-index of a single edited scrap should be <5ms.

**v2 (LLM):**

8. Network inspector during a resolution-detection pass — zero outbound traffic.
9. Loop known to have been addressed in a later scrap → model correctly marks it resolved; marker fades.
10. Loop known to be genuinely unresolved → model says no; marker stays.
11. Ambiguous case → structured output validation should reject unsupported citations; marker stays (high-precision default).
12. Cancellation: navigate away mid-pass → session cancelled, no further compute.
