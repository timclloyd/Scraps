# Plan: Valence Minimap — an ambient semantic strip for the archive

## Context

Scraps is write-only by design. Search lets you find what you can already articulate; the archive lets you scroll what you've written. Neither of these surfaces *shape* — the rise and fall of mood, the density of capture, the silent weeks — over time.

A **valence minimap** — a thin vertical colour strip along the right edge of the archive — renders your scraps' emotional composition as a glanceable timeline. No AI, no interpretation, no ceremony. It's pure presentation of what's literally in your text: the highlight keywords you're already using, refined to carry valence, projected as colour.

This is a deliberate alternative to the earlier Patterns PRD (`2026-04-PRD-patterns.md`), which proposed an on-device-LLM "Review" mode. Both approaches address the same gap — your captures becoming inaccessible because you don't know what to ask — but this one is simpler, deterministic, always-on, and philosophically truer to the app: **it never touches your text, only renders it**.

The Patterns PRD remains in the repo as a retained-for-reference exploration, not the shipping direction.

## Scope

**In scope:**

- Refined highlight keyword set partitioned into valence bands.
- A thin vertical minimap on the archive view, drawn from the valence keywords only.
- Tap-to-scroll: tapping a position on the minimap scrolls the archive to that scrap.
- An active-position indicator showing where the archive is currently scrolled.

**Explicitly not in scope:**

- No LLM, no sentiment *inference* — only explicit keyword hits count.
- No text labels on the minimap. Colour only. Width too tight for anything else.
- No minimap on the latest-scrap panel (only the archive — the minimap is a zoom-out aid, and the latest panel is already zoomed in).
- No user-customisable keyword sets in v1. Ship with sensible defaults; customisation is a later consideration.

## Keyword redesign

Current set is cognitive (`idea`, `fun`, `todo`, `remember`, `important`, `interesting`, `later`) — these don't project onto a valence axis. Replace with three bands:

### Positive (warm hues)
`fun`, `great`, `grateful`, `love`, `happy`, `excited`

### Negative (cool / red hues)
`sad`, `tired`, `anxious`, `angry`, `stressed`, `fuck` / `fucking`
*(The last functions as an emphatic negative marker in actual scraps — worth matching explicitly.)*

### Neutral / cognitive (preserved)
`todo`, `idea`, `remember`, `important`

**How the bands interact:**

- All keywords remain highlighted inline in the editor and archive, as today.
- **Only positive and negative keywords contribute to the minimap.** Neutral / cognitive keywords are editor-only — they're utility markers, not mood signal.
- Each keyword has an assigned colour. Positives share a warm palette (coherent greens / yellows); negatives share a cool palette (reds / blues) — distinct enough to read as separate keywords inside a band but clearly of-a-band at a glance.

## UX

**Position:** trailing edge of the archive view. ~6–8pt wide. Vertical, full height. Does not overlap scraps — archive content insets by the strip width.

**Rendering per scrap row:**

- Fixed row height (e.g. 4–6pt). One row per scrap, chronological.
- Scrap with zero valence keyword hits → rendered as the archive background colour (a silent row).
- Scrap with 1–N valence hits → rendered as N equal-width horizontal segments, each tinted by the corresponding keyword's assigned colour.
- Scrap with > N hits OR when any segment would fall below a minimum pixel width → segments collapse into a single averaged colour (weighted by hit count).
- N is tuned empirically; likely 3–4 segments before blending kicks in, given ~6–8pt row width.

**Active-position indicator:** a small bright chevron or inset bar on the strip marking the currently-visible archive range. Updates as the user scrolls. Makes the minimap function as a semantic scrollbar.

**Interaction:**

- Tap on the strip → scroll the archive to the scrap corresponding to that Y position. Use the same animated scroll already used for search match navigation (`proxy.scrollTo(id, anchor: .top)` + `ScrapPreviewView.scrollToRange`).
- Drag along the strip → scrub through scraps continuously. Bonus, not essential for v1.
- No tap target shown per scrap (the strip is too thin); hit target is the entire strip width.

**Auto-hide (open question):** consider fading the strip out during rapid scroll (like iOS scroll indicators) and fading it back in when scrolling stops. Keeps the archive uncluttered during active reading. Simplest v1: always visible.

**Latest panel:** minimap is hidden on the latest panel. It's an archive feature.

## Architecture

### New files

- `Cache/Views/ArchiveMinimapView.swift` — the strip. Takes `[Scrap]` + valence-hit counts and renders.
- `Cache/Managers/ValenceIndex.swift` — computes and caches per-scrap valence counts from scrap text. Listens for document changes and invalidates. Runs on a background queue; emits `@Published` results.

### Changes to existing files

- `Cache/Managers/TextHighlightManager.swift` — expand `HighlightPatterns` with the valence bands. Each pattern gains a band tag (`positive` / `negative` / `neutral`) and a distinct colour.
- `Cache/App/Theme.swift` — define the positive, negative, and per-keyword colour palette. Existing neutral highlight colour stays.
- `Cache/Views/ArchiveListView.swift` — inset content by the minimap width on the trailing edge; overlay the minimap; wire tap-to-scroll through the existing `proxy.scrollTo` path; publish the current scroll range for the active-position indicator.
- `Cache/Managers/DocumentManager.swift` — no changes. The minimap pulls from `documentManager.scraps` but does not grow the god object.

### Data flow

```
scraps (DocumentManager) ─┐
                          ├─▶ ValenceIndex.compute() ─▶ [ScrapID: [KeywordHit]]
document text changes ────┘                                        │
                                                                   ▼
                                                      ArchiveMinimapView renders
                                                                   │
                                                                   ▼
                                                      tap → ArchiveListView scrolls
```

`ValenceIndex` caches the per-scrap hit map; only the changed scrap is recomputed on edit. For 40 scraps across 5 months this is trivial; even at 1000 scraps the full recompute is milliseconds and only happens on launch or on scrap-set change.

## Reuse from existing code

- `TextHighlightManager.HighlightPatterns` — extend rather than replace. The regex infrastructure is already shared between editor and archive preview (see `CLAUDE.md`).
- `ScrollViewReader` + `proxy.scrollTo(id, anchor: .top)` in `ArchiveListView` — identical to the search-match navigation path built earlier this week.
- `withAnimation(.easeInOut(duration: 0.3))` scroll animation established for cross-scrap search navigation — use the same for minimap taps so the motion feels consistent across features.
- `Theme.archiveBackground` — minimap sits on archive background; silent rows match it so only valence-hit rows draw colour.

## Open questions / assumptions

1. **Positive vs negative colour choice.** Green-vs-red risks medical/warning connotations; yellow-vs-blue might feel less loaded. Try a few palettes early on real data. Accessibility: ensure the chosen pair is distinguishable for red-green colour blindness (deuteranopia affects ~5% of men).

2. **`fuck` as a keyword.** It is genuinely the most-used negative marker in real scraps, but it's also a common emphatic that can be positive in context ("this is fucking great"). Two options: (a) match anyway and accept the noise; (b) require it to stand alone, not adjacent to another valence keyword. Start with (a), simpler.

3. **Case sensitivity.** All keywords should be case-insensitive, matching current `TextHighlightManager` behaviour.

4. **Word boundaries.** Use `\b` boundaries as existing patterns do, so "sadness" doesn't trigger "sad" unless both are wanted — debatable. Probably safer to match word stems explicitly if stemming matters.

5. **Long scraps with many hits.** A scrap with 20 valence hits shouldn't dominate the minimap visually; the blend-collapse rule handles this, but we should check real scraps to confirm the threshold feels right.

6. **Empty scrap rows.** Silent days (no valence hits) are meaningful information — avoid drawing them as background-coloured (invisible), consider a very faint tint so "I wrote something but nothing emotionally marked" reads differently from "I wrote nothing." Possibly out of scope for v1 — start with invisible silent rows.

7. **iPad / Mac layouts.** On iPad and Mac the archive has more horizontal room; the minimap could be wider (8–12pt) and show richer segment detail. Platform-scale via `Theme.isIPhone` vs `Theme.isIPadOrMac` check.

## Phasing

Smaller than the Patterns PRD's phasing. Single coherent v1, then optional polish.

**v1** — ship the whole feature:
- Refined keyword set + palette.
- `ValenceIndex` with scrap-level caching.
- `ArchiveMinimapView` with multi-segment rendering, blend-collapse, tap-to-scroll, active-position indicator.
- Fixed 4–6pt row height, always-visible strip.

**v1.1 polish (if wanted):**
- Drag-to-scrub.
- Auto-fade during archive scroll.
- User-customisable keyword set.
- Platform-specific minimap widths.

## Verification

1. Build + run. Open archive on a corpus with known keyword distribution. Visually confirm minimap colour composition matches the scraps' content.
2. Add a valence keyword to a scrap — verify the corresponding minimap row updates without restart.
3. Tap various positions on the minimap — verify the archive scrolls to the expected scrap with the existing animation curve.
4. Scroll the archive manually — verify the active-position indicator tracks the visible range.
5. Corpus with very long scraps (many keyword hits) — verify the blend-collapse threshold produces a sensible averaged colour, not visual chaos.
6. Corpus with zero valence keywords across all scraps — verify the minimap renders as uniformly silent without crashing.
7. Accessibility: run with Smart Invert Colors and with a red-green colour-blindness simulator — confirm positive / negative bands are still distinguishable.
8. Performance: on a 1000-scrap corpus, measure `ValenceIndex` initial compute + incremental update times. Target < 100ms initial, < 5ms incremental.

---

## Scaling notes — 2026-04-21

The current implementation (one row per scrap, opacity encodes hit count) will hit a practical floor around 200–300 scraps, when each row is ~3px tall and individual band segments are barely a pixel high.

**Time bucketing** is the natural response: group scraps into weeks (or months) and aggregate their hits into a single row, switching automatically based on scrap count to keep rows above a usable minimum height. The opacity encoding already generalises cleanly to aggregates — more total hits in a week means more saturated colour.

**Non-uniform bucketing** is worth exploring: bucket more coarsely towards the bottom (older scraps) than the top (recent). This mirrors how memory naturally compresses the past, and conveniently keeps recent scraps at fine granularity where precise navigation matters most, while aggregating old ones where approximate navigation is sufficient.

**Interaction at scale**: once rows represent weeks rather than individual scraps, tap/scrub lands you at the start of a week rather than a specific scrap. This decouples minimap touch position from exact scroll position, which is fine — the minimap becomes a coarse temporal index rather than a 1:1 scroll proxy. A natural two-stage gesture follows: drag the minimap for coarse week-level jumping, release and use the normal scroll for fine-tuning within the week. No new UI required.
