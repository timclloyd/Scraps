# PRD: Automatic Scrap Separators

**Status:** Draft
**Created:** 2025-01-11
**Last Updated:** 2025-01-11

---

## Overview

Add automatic time-based separators that divide the continuous text into discrete "scraps" based on usage patterns. Inspired by Drafts app's auto-new-note behavior, but adapted to Scraps' continuous text model.

**Core Concept:** Each scrap is stored as a separate iCloud document file. When the app is opened after being suspended/quit for more than 1 minute, create a new scrap document. The UI displays all scraps in chronological order (oldest first, newest last) as a seamless scrollable view with visual separators between them. New scraps appear at the bottom, maintaining the feel of a continuously growing document.

---

## Goals

1. **Feel like continuous text flow** - Even though each scrap is a separate document, the UI should present them as one seamless scrollable view
2. **Add useful structure** - Enable features like copy/delete individual scraps
3. **Feel natural** - New scraps created when contextually appropriate (new session = new thought)
4. **Clean separation** - Each scrap is independent, no editing across boundaries

---

## Non-Goals

- Separate files for each scrap
- Manual separator insertion (for v1 at least)
- Complex scrap management UI

---

## Design Decisions

### 1. Timing & Triggers

**When to create a new scrap:**
- App is opened after being **suspended (iOS) or quit (macOS)** for >1 minute
- On macOS: If app is just backgrounded (behind other windows) but still running, do NOT create new scrap when foregrounded
- Force quit DOES reset the timer (should trigger new scrap on next open)

**When NOT to create new scrap:**
- App was just backgrounded briefly (<1 minute)
- App is still running but covered by other windows (macOS)
- First launch (no previous session)

**Edge case - Multi-device usage:**
- Initially: ignore this complexity, see what happens naturally with iCloud sync
- Example scenario: Open on Mac, immediately open on iPhone
  - Likely both will think they should insert separator
  - iCloud conflict resolution will pick one version
  - User might see duplicate separators briefly
  - **Decision:** Accept this as acceptable v1 behavior, iterate later if problematic

**Implementation approach:**
- Track "last close time" in UserDefaults (local to each device)
- On app active, compare current time to last close time
- If >30s AND text is non-empty, insert separator at end of document

---

### 2. Visual Design

**Format:**
```
2025-11-11 10:41 - - - - - - - - - - - - - - - - - - -
```

**Specifications:**
- **Color**: `UIColor.systemGray3` (defined in `Theme.swift` as `separatorColor`)
- **Timestamp format**: ISO date + 24h time (`yyyy-MM-dd HH:mm`)
- **Timestamp visibility**: Always visible
- **Layout**:
  - Timestamp text on left
  - Dotted line extends from timestamp to right edge of text area
  - Responsive: grows/shrinks with window resize (macOS) and orientation changes (iOS)
- **Width**: Same as text content width (respects `Theme.horizontalPadding`)
- **Vertical padding**: Uses existing `Theme.verticalPadding` constant (48pt above and below)

**Implementation notes:**
- Dotted line implemented as repeating "- " characters OR custom SwiftUI view
- Must be dynamically calculated based on available width and timestamp width
- Should maintain consistent spacing between dashes regardless of window size

---

### 3. Data Model

**Architecture:** Multiple iCloud document files, one per scrap

**File naming:**
- Filename format: `scrap-YYYY-MM-DD-HHmmss.txt` (includes seconds for uniqueness)
- Example: `scrap-2025-01-11-104153.txt`
- Displayed in UI as: `2025-01-11 10:41` (no seconds shown)
- Timestamp embedded in filename (no need to store separately)
- Chronological sorting by filename

**File location:**
- Same as current: `iCloud/Documents/`
- Current file: `scraps.txt` (single file)
- New pattern: `scrap-*.txt` (multiple timestamped files)

**File content:**
- Pure user text content only
- No metadata, no separators in the text itself
- Plain UTF-8 text files

**Separator rendering:**
- Separators are pure UI (SwiftUI views between scrap text editors)
- Parse timestamp from filename for display
- Fully responsive width (no fixed-character issues)

**Document management:**
- Each scrap managed by its own `UIDocument` instance
- Keep in-memory array of all scrap documents sorted chronologically
- Same UIDocument sync model as current implementation (just managing multiple instances)

---

### 4. Scrap Interactions

**Interaction model (v1 - Keep it simple):**
- Each scrap is an independent text editor
- Tap a scrap to edit it (gain focus)
- Arrow keys/cursor only work within the current scrap
- Cannot edit across scrap boundaries
- To edit a different scrap, tap it

**Visual feedback:**
- Currently editing scrap: subtle highlight/border (or no special treatment)
- Other scraps: neutral appearance
- Clear visual indication of which scrap has focus (if needed)

**Not included in v1:**
- Copy scrap functionality
- Delete scrap functionality
- Keyboard navigation between scraps
- Collapse/expand scraps

These can be added in future iterations once the core multi-file architecture is stable.

---

### 5. Migration & Backwards Compatibility

**Migration strategy:**

**One-time migration on first launch after upgrade:**
1. Check if old `scraps.txt` file exists
2. If yes, read its content
3. Create a new scrap file with current timestamp: `scrap-YYYY-MM-DD-HHmmss.txt`
4. Copy all existing text into this new scrap
5. Leave `scraps.txt` in iCloud (don't delete, don't modify)
6. All existing content becomes the first scrap with a normal timestamp

**Post-migration behavior:**
- First scrap shows timestamp of migration (current time)
- App continues as normal - as if user had entered all that text on first launch
- Next time app is opened (after >1 minute), a new scrap is created normally
- User continues from where they left off

**Note:** Migration is one-way, but old file remains in iCloud as implicit backup.

---

### 6. Edge Cases

**Tiny scraps:**
- What if: Open, type one character, close, wait >1 min, open again
- Decision: Allow tiny scraps, treat as normal
- No minimum size requirement

**Empty scraps:**
- What if: App opened, >1 min elapsed, but user types nothing (or only whitespace/newlines)
- Decision: Don't save empty scraps
- Only create scrap file when user types actual content (non-whitespace characters)
- Empty TextEditor should not result in saved file

**Maximum scraps / Performance:**
- v1 decision: Don't add limits or worry about performance yet
- See how it performs in practice
- Can optimize later if needed

**Same-minute scraps (timestamp collision):**
- Problem: Two scraps created within same minute could collide
- Solution: Store full ISO timestamp with seconds in filename
  - Filename: `scrap-2025-01-11-104153.txt` (YYYYMMDDHHmmss)
  - Display in UI: `2025-01-11 10:41` (YYYY-MM-DD HH:mm, no seconds)
- This ensures unique filenames while keeping UI clean
- Files will sort correctly chronologically

---

## Technical Considerations

**Implementation areas:**
- Multi-document management: Managing array of UIDocument instances
- ScenePhase monitoring: Detect when to create new scrap (already implemented)
- UserDefaults: Track last close time per device
- File discovery: Enumerate existing scrap files on launch
- SwiftUI ScrollView: Display all scraps as seamless vertical list
- Separator UI component: Custom view showing timestamp + dotted line
- Focus management: Track which scrap is currently being edited
- Migration logic: One-time conversion from `scraps.txt` to first scrap file

**Performance:**
- Each scrap is a separate UIDocument (lazy loading)
- Should scale reasonably with hundreds of scraps
- Can optimize with virtual scrolling later if needed

---

## Open Questions

1. How do we handle multi-device race conditions better in v2? (Deferred)
2. Should we add keyboard navigation between scraps in v2? (Deferred)

---

## Next Steps

1. Prototype multi-document architecture
   - Update DocumentManager to handle multiple UIDocument instances
   - Implement file enumeration on launch
   - Create scrap list UI
2. Implement separator UI component
3. Add new-scrap creation logic (1-minute threshold)
4. Implement migration from `scraps.txt`
5. Test on all platforms (iOS/iPad/Mac)
6. Test with iCloud sync across devices
