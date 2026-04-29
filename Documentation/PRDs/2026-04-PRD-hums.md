# Plan: Hums — a minimal audio capture app for voice and musical fragments

## Context

Scraps is text. Inklings is sketch. Hums is the audio sibling — the same "small, fast, pre-polish" capture philosophy applied to sound.

The shape we want to preserve across the family:

- **Capture is cheap.** One gesture, no setup, no titling, no tagging.
- **The archive is chronological and passive.** You visit it when curious; the app never pushes.
- **The file is the unit.** One capture = one plain file, iCloud-synced, independently meaningful.
- **No polish tools.** These apps capture upstream of polish; if you want to edit, export to a tool that exists for editing.

Hums covers two overlapping use cases the other two apps can't:
- **Voice memos** — a quick thought spoken aloud because typing is slower, or because your hands are busy (walking, driving, cooking).
- **Musical fragments** — a hummed melody, a whistled hook, a tapped rhythm, a sung lyric idea.

These two share more than they differ: both are sound captured in the moment, both need to be playable back, both are almost always short, both resist tidy titling.

## The central design problem: retrieval

Scraps solves retrieval with scrolling + search + (planned) valence minimap. Inklings presumably uses visual thumbnails — sketches are their own preview.

**Audio has no preview.** You cannot visually scan 40 voice memos and find "the one from last Tuesday about the conference". A waveform tells you almost nothing about content. Playback is linear and slow — scanning 40× 30-second clips takes 20 minutes.

This is the single hardest problem in the app. Every architectural decision flows from how we answer it.

**The likely answer: transcription-as-shadow.**
- On-device `Speech` framework transcribes voice captures in the background.
- The transcript is *not* the content — the audio is. But the transcript is the *index*.
- Archive view shows each capture as: waveform thumbnail + timestamp + transcript excerpt (or "(musical fragment)" if no speech detected).
- Search queries the transcript corpus the same way Scraps searches text.
- Tap a result → plays the audio, highlights the spoken range.

**Musical fragments are the hard subcase.** A hummed melody produces no transcript. Options, in ascending ambition:
1. **Label it as "(musical)" and rely on date + waveform + listening.** Simplest, ships first.
2. **Extract a rough pitch contour** from the audio and render it as a tiny glyph beside the waveform. Deterministic, no ML. Gives visual differentiation between "rising phrase", "repeated note", "descending line".
3. **Key / tempo detection** for longer musical captures. Useful for musicians revisiting ideas. Standard DSP, no ML.
4. **(Much later, speculative)** on-device music-to-MIDI-ish for hummed melodies. Apple doesn't ship this; third-party models are large. Probably out of scope for v1 and v2.

The user's audio-processing background is the main reason this is tractable at all — options 2 and 3 are straightforward for someone who's done DSP, and they'd be novel in a capture app.

## Scope

**In scope (v1):**

- One-gesture record: tap to start, tap to stop. No arm/disarm, no countdown.
- Chronological archive of captures.
- Waveform thumbnail per capture, generated at record time.
- On-device speech transcription (voice captures) as the searchable shadow.
- "(Musical)" label for captures with no detected speech.
- Tap-to-play, scrubbable playback.
- iCloud sync (same UIDocument-style pattern as Scraps, adapted for audio).
- Delete a capture.

**In scope (v2):**

- Pitch-contour glyph for musical captures.
- Search across transcripts.
- Key / tempo detection for longer musical captures (>8 seconds, say).

**Explicitly not in scope:**

- No editing. No trim, no crop, no silence-removal. The capture is the capture.
- No overdubbing or multi-track. This is not a DAW, not even a mini one. If you want to layer, export.
- No filters, no EQ, no noise suppression beyond whatever iOS gives us for free at the input stage.
- No background recording. App must be foreground — privacy-obvious, battery-sane.
- No cloud transcription. On-device `Speech` only.
- No sharing / export UI beyond iOS's standard share sheet on a capture.
- No folders, no tags, no favourites. Chronological only, like Scraps.

## Trust contract

Same spirit as the Scraps / Patterns trust contract:

1. **Nothing leaves the device without explicit user action** (share sheet = explicit).
2. **Transcription is on-device.** No cloud `Speech` API usage.
3. **Captures are immutable.** The app never rewrites the audio file. Transcription is stored as a sidecar, not burned in.
4. **Recording is unambiguous.** A visible, unmistakable recording indicator is on the whole time the mic is live. No "was it recording? I can't tell" state. The iOS orange mic dot is a backstop, not the primary signal.
5. **Mic permission is asked once, at first tap.** No pre-flight permission prompts on launch.

## UX

### Capture gesture

- The app opens directly into a capture-ready state. No modal, no setup.
- Primary affordance: a large tap target (button or waveform-lit area) in the centre of the screen.
- First tap: request mic permission (first launch only), begin recording. Timer + live waveform.
- Second tap: stop. File is written, thumbnail generated, transcription kicked off async.

**Hold-to-record vs tap-to-toggle?** Both have precedent. Tap-to-toggle wins because:
- Walking / driving / hands-busy are explicitly target use cases; holding a button ties up a hand.
- Musical fragments can run 30s+ and holding that long is ergonomically bad.
- Accidental-start risk is symmetrical with accidental-stop risk; tap-to-toggle gives you visible feedback either way.

### Archive

Chronological list, newest last (matching Scraps). Each row:

```
[waveform thumbnail]  Mon 14:22   "so the thing about the conference is…"    0:43
[waveform thumbnail]  Mon 14:25   (musical)                                    0:12
```

- Waveform thumbnail: static PNG or vector, computed once at record time. Small (~80×32pt).
- Timestamp: day + time-of-day.
- Transcript excerpt: first ~8 words if voice; "(musical)" placeholder otherwise.
- Duration: right-aligned.

Tap a row → play inline. The row expands to show full transcript (if any) + full waveform + scrubber.

### Playback

- Tap-to-play, tap-to-pause.
- Drag the waveform to scrub.
- Playback speed: 1×, 1.5×, 2× (useful for voice memos; musicians can stick to 1×). Long-press on playhead toggles.
- No loop regions in v1.

### Recording indicator

Whenever the mic is live, a prominent red band sits across the top of the screen. Not a subtle dot — a band. The moment recording stops, the band vanishes.

## Architecture

### Files on disk

Mirrors Scraps' "one capture = one file" shape:

- `hum-YYYY-MM-DD-HHmmssZ.m4a` — the audio, AAC-encoded at a sensible bitrate (96–128 kbps mono). Lossless is overkill for humming and voice memos; AAC is what the iOS recorder produces natively and it's tiny.
- `hum-YYYY-MM-DD-HHmmssZ.json` — sidecar with transcript, waveform peak data, pitch contour (v2), key/tempo (v2), detected language. Regenerable from the audio, but caching avoids re-running transcription on every launch.

Both in the same iCloud container, same `NSFileCoordinator` pattern as Scraps.

### Recording pipeline

`AVAudioEngine` input tap → writes to `AVAudioFile` (m4a) → simultaneously feeds a peak-extraction buffer for the live waveform display. On stop:

1. Close the file (durable on disk).
2. Walk the peak buffer to produce the waveform thumbnail; write as part of the sidecar JSON.
3. Kick off on-device `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true`.
4. When transcription returns, update the sidecar.

Steps 2–4 are non-blocking. The capture is immediately visible in the archive with waveform + "transcribing…" state; transcript fills in asynchronously.

### Capture vs platform

- iPhone: primary. One-handed, always on you.
- iPad: works, but niche — you don't tend to grab an iPad to hum into it.
- macOS (Catalyst): playback + archive browsing only? Or full capture? Worth deciding — Macs have mediocre built-in mics and people tend to have better ways to record on a desk. Lean towards capture-optional on Mac, archive-first.

### New files (sketch)

- `Hums/App/HumsApp.swift`
- `Hums/Managers/RecordingController.swift` — owns `AVAudioEngine`, lifecycle, recording indicator state.
- `Hums/Managers/HumDocument.swift` — `UIDocument` subclass for audio + sidecar.
- `Hums/Managers/HumLibrary.swift` — the Scraps-`DocumentManager` analogue (but learning from the complexity review: ship this split from day one, don't let it become a god object).
- `Hums/Managers/TranscriptionService.swift` — wraps `SFSpeechRecognizer` with on-device-only enforcement.
- `Hums/Managers/WaveformRenderer.swift` — peak extraction + thumbnail generation.
- `Hums/Models/Hum.swift` — `{ id, timestamp, filename, duration, transcript?, waveformPeaks, pitchContour? }`.
- `Hums/Views/CaptureView.swift`, `ArchiveView.swift`, `HumRowView.swift`, `PlaybackView.swift`.

## Open questions / assumptions

1. **Bitrate / codec.** AAC 96 kbps mono is the default assumption. For musical captures specifically, 128 kbps might be worth the extra bytes — but every capture going to 128 is fine too; at 30s average, storage is negligible.

2. **Sample rate.** 44.1 kHz is the obvious musical default; 22.05 kHz is plenty for voice. Probably not worth branching — pick one (48 kHz native iOS mic rate → downsample to 44.1 on save) and move on.

3. **Live waveform resolution during recording.** Peak-per-frame at display refresh is fine for the live view. For the stored thumbnail, ~200 peaks across the clip is enough for an 80pt-wide render.

4. **Speech language detection.** `SFSpeechRecognizer` needs a locale. Auto-detect via `NLLanguageRecognizer` on the transcription result? Or rely on the device locale? Device locale is fine for v1.

5. **Voice vs musical classification.** How do we decide a capture is "(musical)"? Simplest: speech transcription returned empty / very low confidence → show as musical. Slightly better: run a quick voicing detector (zero-crossing rate + spectral rolloff) at record time. Your DSP background makes option 2 tractable but option 1 is probably good enough for v1.

6. **Silence trimming at record start/stop.** Tempting — tapping the button introduces a click and a half-second of fumbling at each end. But trimming violates "captures are immutable". Possible compromise: trim on *playback* (skip leading/trailing silence below a threshold), leave the file itself untouched. Revisit post-v1.

7. **Accidental ultra-short captures.** Tap-tap sequences under ~0.5s are almost certainly mistakes. Silently discard, or keep and let the user delete? Scraps keeps empty-ish scraps (and then cleans them up on background). Hums could do the same — discard captures shorter than a threshold at record-stop time.

8. **Pitch contour glyph (v2) design.** A 12-point-wide sparkline of fundamental frequency over time, log-scale, normalised to the capture's min/max. Rendered as a tiny SVG-style path beside the waveform. This is where your intuitions probably matter most — what contour representation actually helps a musician recognise "oh yeah, *that* hook"?

9. **Archive row vs dedicated playback screen.** Inline expansion is nicer but constrains scrubber width. A dedicated screen on tap is more generous but adds navigation. v1: inline. Revisit if scrubbing precision bites.

10. **Transcription correction.** Should the user be able to correct a bad transcript? Aligns with "captures are immutable" if we say the *audio* is immutable but the sidecar is editable. Probably yes, eventually — bad transcripts poison search. Out of scope for v1.

11. **Integration with Scraps / Inklings.** Do captures in one app ever surface in another? Tempting to say no (each app is its own thing) but there's a latent "unified timeline" product here if the family grows. Explicit non-goal for v1; keep the door open architecturally by making timestamps the lingua franca.

## Phasing

**v1 — Capture + archive + transcription.**
- Recording, waveform thumbnail, chronological archive, inline playback, on-device transcription, iCloud sync, delete.
- Ships as a usable voice-memo replacement with musical captures working (just without musical-specific affordances yet).

**v2 — Musical affordances.**
- Pitch-contour glyph for musical captures.
- Search across transcripts.
- Voicing detector to reliably tag musical vs voice.

**v3 — Polish / platform.**
- Key / tempo detection for longer musical captures.
- macOS behaviour decisions.
- Transcript correction.
- Playback speed control.

## Verification

**v1:**

1. Record a 10s voice memo. Confirm file written, waveform appears, transcript populates within a few seconds, searchable in archive.
2. Record a 10s hum. Confirm file written, waveform appears, transcript is empty or "(musical)"-labelled.
3. Airplane mode: record + transcribe. Confirm transcription completes offline (on-device enforcement).
4. Multi-device iCloud: record on device A, open on device B, confirm capture appears + plays + transcript present.
5. Kill the app mid-recording (force-quit). Confirm the partial file is either recovered or cleanly discarded — not a zero-byte ghost.
6. Scrub playback on a 60s capture. Confirm scrub tracks smoothly and audio seeks correctly.
7. Mic permission denied state: confirm the recording button surfaces a clear "enable microphone" prompt, not a silent failure.
8. Background the app during recording. Confirm recording stops cleanly (we're not doing background recording).
9. Performance: open archive with 500 captures. Confirm scrolling is smooth; thumbnails don't re-render on scroll.
