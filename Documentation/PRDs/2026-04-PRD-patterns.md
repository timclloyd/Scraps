# Plan: Passive Patterns — on-device pattern surfacing

## Context

Scraps is write-only by design: you type, it syncs, done. That's the strength, but it's also a gap — nothing surfaces anything *back* to you. Search only works when you already know what to look for. Over months, your own captures become inaccessible not because they're lost but because you don't know what to ask.

A **Patterns** mode complements capture with reflection, *without* breaking the philosophy:

- Passive (app never pushes, you visit when curious)
- On-device (scraps never leave the phone)
- Grounded (every surfaced result cites the exact scraps that produced it)
- Read-only (LLM never rewrites your text)

This is the anti-hoarding inverse of a share sheet: instead of *adding* external content to collect, it *illuminates* what you already captured.

## Scope

Pattern kinds to support, in priority order (drives shipping sequence):

1. **Dormant threads** — todos/intentions/questions you never returned to.
2. **Recurring themes** — topics you keep coming back to.
3. **Sentiment correlation** — "you tend to feel X on days involving Y".
4. **Anniversaries** — "a month / year ago you wrote…". Pure date math, no LLM.

Non-scope (explicit):

- No "unexpected connections" detection. Dropped entirely — too high a hallucination risk for too thin a reward.
- No text rewriting, editing, or transformation of scraps by LLM.
- No cloud LLMs. On-device only (Apple `FoundationModels` framework, iOS/macOS 26+).
- No push notifications. No background compute.
- Cadence: on-demand — user taps "Patterns", results compute in that moment.

## Trust contract

Non-negotiable invariants — if we break any of these, the feature fails the app's philosophy:

1. **Nothing leaves the device.** No network calls in the pipeline.
2. **Every `PatternResult` cites scraps.** Tap a result → jump to the exact scrap (and range within) that produced it. No unsupported summaries.
3. **LLM output is never written back.** Scrap text is immutable from this feature's perspective.
4. **User can dismiss results.** Dismissed results don't reappear.
5. **Graceful degradation.** On devices below iOS 26, Patterns shows anniversaries only — no feature gate that confuses the user.

## UX

**Entry point:** toolbar gains a new mode (`.patterns`) alongside `.latest` / `.archive`. Use the same panel-slide animation pattern (`Theme.navigationIn` / `navigationOut`).

**Patterns view:** scrollable list of **result cards**. Each card:

- A short LLM- or rule-generated summary (one or two lines).
- 1–4 citations, each a tappable snippet showing the source scrap excerpt.
- Tap a citation → navigates to archive, scrolls to the cited scrap, highlights the cited range (reuse the search-match `activeSearchRange` + `scrollRectToVisible` path in `ScrapPreviewView`).
- Swipe-to-dismiss per card.

**Refresh:** pull-to-refresh recomputes. Show a subtle "last run" timestamp and a rough progress indicator while the model runs.

**Empty state:** when there aren't enough scraps yet, show a friendly "keep writing" message rather than broken cards.

## Architecture

Respecting the recent complexity review (don't grow `DocumentManager`):

### New files

- `Cache/Models/PatternResult.swift` — `struct PatternResult { kind, title, body, citations: [Citation], id, generatedAt }` + `struct Citation { scrapID, range: NSRange, excerpt: String }`.
- `Cache/Patterns/PatternEngine.swift` — orchestrator. Owns a `detect()` method taking `[Scrap]` and returning `[PatternResult]`. Composed of detectors:
  - `DormantThreadDetector`
  - `ThemeDetector`
  - `SentimentCorrelationDetector`
  - `AnniversaryDetector` — pure Swift, no model.
- `Cache/Patterns/LanguageModelClient.swift` — thin wrapper over `FoundationModels.LanguageModelSession`. Handles availability, structured output (`Generable` types), batching, and token-budget-aware chunking. One place to mock in tests.
- `Cache/Views/PatternsView.swift` — the new panel view, mirroring `ArchiveListView` structure.
- `Cache/Views/PatternCardView.swift` — presentation of a single `PatternResult`.

### Changes to existing files

- `Cache/Views/MainView.swift` — add `.patterns` case to `ViewMode`, route transitions through `Theme.navigationIn/Out`.
- `Cache/Views/ToolbarView.swift` — new mode affordance.
- `Cache/App/Theme.swift` — pattern-card styling tokens.

### Why a new module rather than extending `DocumentManager`

`DocumentManager` is already a god object (per `Documentation/Reviews/2026-04-19-complexity-review.md`). Patterns has zero sync responsibilities — it *reads* from `documentManager.scraps` and produces its own state. Keeping it in a separate `Patterns/` module avoids compounding that complexity debt.

### Data passed to the model

The LLM only ever sees:
- Plain text of scraps within the window (e.g. last 90 days for themes/sentiment).
- No user identifiers, no filenames beyond what's needed to cite back.
- Day-level timestamps (from `Scrap.timestamp`) — no sub-day precision needed.

### Structured output for grounding

Each LLM-backed detector requests structured output via `@Generable` types:

```swift
@Generable
struct ThemeCandidate {
    let title: String
    let summary: String
    let citedScrapIDs: [String]   // must be subset of input IDs
}
```

At return time, the detector validates every `citedScrapIDs` entry is a real scrap ID. Hallucinated IDs get dropped; if that empties the citations, the `PatternResult` itself gets dropped. This is the primary hallucination defence.

## Phasing

Priority order drives shipping sequence. This commits to LLM infrastructure in Phase 1 — higher upfront engineering cost than starting with anniversaries, but delivers the highest-priority pattern first.

**Phase 1 — Patterns scaffold + Dormant threads.**
- New `.patterns` mode, view, navigation, card component.
- `LanguageModelClient` wrapper (minimal, what Dormant needs).
- `DormantThreadDetector` with citation-grounded structured output.
- Validates UX, animation fit, LLM pipeline, and trust contract in one shot.

**Phase 2 — Recurring themes.**
- `ThemeDetector` reuses most of the Dormant infrastructure; primarily a prompt + schema change.

**Phase 3 — Sentiment correlation.**
- Hardest: requires day-level aggregation and cross-day correlation.
- Two-pass approach: per-scrap feature extraction (sentiment + topics) cached, then correlation computed over the cache.

**Phase 4 — Anniversaries.**
- `AnniversaryDetector` — pure date math, no LLM. Cheapest to build but lowest priority.
- Ships last but also acts as the sub-iOS-26 graceful-degradation fallback (point 5 in the trust contract), so worth shipping even at low priority.

## Critical files to modify / create

Create:
- `Cache/Models/PatternResult.swift`
- `Cache/Patterns/PatternEngine.swift`
- `Cache/Patterns/LanguageModelClient.swift`
- `Cache/Patterns/Detectors/DormantThreadDetector.swift` (Phase 1)
- `Cache/Patterns/Detectors/ThemeDetector.swift` (Phase 2)
- `Cache/Patterns/Detectors/SentimentCorrelationDetector.swift` (Phase 3)
- `Cache/Patterns/Detectors/AnniversaryDetector.swift` (Phase 4)
- `Cache/Views/PatternsView.swift`
- `Cache/Views/PatternCardView.swift`

Modify:
- `Cache/Views/MainView.swift` — add `.patterns` to `ViewMode`, transition wiring.
- `Cache/Views/ToolbarView.swift` — surface the new mode.
- `Cache/App/Theme.swift` — card styling.

## Reuse from existing code

- `Theme.navigationIn` / `navigationOut` — match the animation feel.
- `ScrapPreviewView.scrollToRange` — tapping a citation should drive the same animated scroll used for search.
- `activeSearchRange` + `activeMatchScrapID` flow in `ArchiveListView` — a citation tap just sets these after switching to `.archive` mode.
- `documentManager.scraps` — sole data source; no re-enumeration.

## Model choice

Apple `FoundationModels` (on-device ~3B) is the chosen model. Quality is adequate *if* the architecture stays inside the model's competence window: per-scrap extraction + deterministic aggregation + short per-cluster summary. No free-form multi-document synthesis.

Known weak points:
- Dormant matching (semantic similarity across months) is the quality-sensitive piece. Ship with a conservative threshold — better high-precision / low-recall than hallucinated matches.
- Very terse or metaphorical scraps extract poorly.
- First-call warmup latency.

Third-party MLX models considered and rejected for v1: 4–8GB app-size cost and a philosophical shift (shipping a model inside a plain-text app) outweigh the quality gain.

## Open questions / assumptions

1. **iOS version floor.** `FoundationModels` is iOS/macOS 26+. What's the project's deployment target? If older, Phase 4 (anniversaries) covers graceful degradation, but Phases 1–3 are gated on OS availability.
2. **Cost of a pass.** Full-window analysis could take many seconds on-device. Need to time-box: show cards as they generate, cancel mid-run when user navigates away.
3. **Scrap size.** Some scraps are long; token budget per detector call matters. Likely need a summarise-then-analyse pipeline for long scraps.
4. **Citation excerpt selection.** The model should return the scrap ID + a short verbatim excerpt that grounds the claim; we then locate the excerpt by string search to recover the exact `NSRange`.
5. **Caching.** Are results cached between visits? Simplest v1: no cache — every visit recomputes. Later: cache keyed on `(scrapIDs hash, window, detector version)`.

## Learnings from prototype pass

Before writing this plan, a manual pass over ~40 real scraps (5 months of data) was used as a prototype of what Patterns might surface. Several design implications fell out that should shape the implementation:

1. **Dormant threads are the highest-signal pattern kind.** Themes describe what the user writes *about*; dormant threads describe what they said they'd *do*. The latter is actionable; the former is observational. Reinforces Phase 1's choice of Dormant as the first shipping detector.

2. **Short scraps are noise.** Single-word captures ("Urgh", "Thing", "Hello there") inflate counts and produce weak citations. `PatternEngine` should filter input by a minimum length/information threshold before passing scraps to any detector — including `AnniversaryDetector`, which otherwise happily resurfaces one-word entries.

3. **Duplicate / near-duplicate scraps must be collapsed.** The prototype corpus contained the same paragraph captured four times across two days. Left un-deduplicated, the model wastes tokens and the resulting cards feel repetitive ("you've written about this 4 times!" when it's the same thought captured 4 times, not 4 distinct occurrences). Collapse near-duplicates with a simple similarity threshold before feeding to detectors, and cite them as a single "captured 4× in 2 days" unit.

4. **Sensitive content requires care.** Real scraps contain mental-health, substance-use, and other personal material. The feature's value depends on surfacing these honestly, but the model must be instructed to: (a) cite via verbatim quotation, never paraphrase; (b) never offer advice, diagnosis, or interpretation; (c) never generate language the user didn't themselves write. Essentially: the model is a librarian, not a therapist.

5. **Self-notes ("Remember…") deserve a dedicated detector.** When the user writes an instruction to their future self, resurfacing it is the cleanest possible pattern — it needs no LLM judgement, just pattern-matching on imperative self-address ("Remember…", "Note to self…", "Next time…"). Worth promoting to its own small detector, possibly ahead of Sentiment in priority — it's cheap, high-precision, and deeply on-brand for the app.

## Verification

**Phase 1 verification (scaffold + Dormant threads):**

1. Build + run on iOS 26 simulator. From `.latest`, navigate to `.patterns`. Animation should match `.latest` → `.archive` feel.
2. With a test corpus containing a few obvious dormant todos ("want to try X", "remember to do Y" from months ago), verify Dormant cards appear with correct excerpts.
3. Tap a citation — verify it switches to `.archive`, scrolls to the scrap, and highlights the correct range (mirrors search behaviour).
4. Dismiss a card — verify it doesn't reappear on refresh in the same session.
5. Verify empty state when no qualifying scraps exist.
6. Network inspector during a pass — expect zero outbound traffic.
7. Feed the model a corpus with known-false planted IDs in adjacent text; verify no hallucinated IDs survive validation to the UI.
8. Cancellation: navigate away mid-generation — verify the session is cancelled and doesn't consume further compute.

**Phase 2+ additional verification:**

9. Themes: multi-run stability check — same corpus run 3× should produce broadly overlapping themes (not wildly different every pass).
10. Sentiment: ground-truth check — feed a known-positive and known-negative day; verify polarity lands correctly before trusting correlations.
11. Accessibility: pattern cards readable by VoiceOver; citations describe their source scrap date.
