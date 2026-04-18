# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**Last Updated:** 2026-04-18

## Maintenance Protocol

This file requires periodic updates as the codebase evolves. To keep it accurate:

1. **When to update:**
   - After adding/removing major features
   - When architectural patterns change
   - After refactoring core systems (sync, highlighting, document management)
   - When file structure changes significantly
   - After updating dependencies

2. **How to update:**
   - Run `/review-claude-md` to analyze the current codebase and get suggested updates
   - Manually edit this file with the suggestions
   - Update the "Last Updated" timestamp above

3. **What to prioritize:**
   - Keep "Key Architecture" section accurate (most important)
   - Update line number references if files change significantly
   - Verify "Development Commands" still work
   - Check "Common Tasks" reflect current best practices

## Project Overview

**Scraps** (formerly "Cache") is a minimal, fast text capture app for iPhone, iPad, and macOS. It uses iCloud sync via UIDocument to keep plain text scraps synchronized across devices. The app emphasizes speed and simplicity - no folders, no formatting, just text.

## Key Architecture

### Multi-Document Model
Unlike typical note apps with a single text file, Scraps uses **multiple text documents** (one per scrap):
- Each scrap is a separate `.txt` file in iCloud: `scrap-YYYY-MM-DD-HHmmss.txt`
- Files are sorted chronologically (oldest first)
- New scraps are automatically created when the app returns from background on a new calendar day (checked via `calendar.isDate(_:inSameDayAs:)` against the latest scrap's timestamp)
- Empty scraps are automatically deleted when the app backgrounds

### iCloud Sync Pattern (Critical)
This app implements **UIDocument-based iCloud sync** - see `Documentation/icloud-sync-best-practices.md` for comprehensive sync implementation patterns.

**Key principles:**
- All file I/O goes through `UIDocument` (never direct file operations)
- Saves are **immediate on every text change** (no debounce) - UIDocument handles coalescing internally
- Uses **ScenePhase** for lifecycle management (handles macOS Cmd+Q correctly)
- Implements **last-writer-wins** conflict resolution (iOS requires manual conflict handling)
- Checks for updates when app becomes active
- Saves before backgrounding/termination

**Critical files:**
- `Cache/Managers/TextDocument.swift` - UIDocument subclass for text serialization
- `Cache/Managers/DocumentManager.swift` - Manages multiple scraps, handles lifecycle, sync, and conflicts

### Text Highlighting Architecture
Real-time keyword highlighting uses a custom `NSLayoutManager`:
- `TextHighlightManager.swift` extends `NSLayoutManager` to apply styling during text layout
- Only processes **changed lines** (not entire document) for performance
- Highlights keywords: "idea", "fun", "todo", "remember", "important", "interesting", "later"
- Detects and makes URLs tappable
- Styling updates automatically as user types (no lag)

### Platform-Specific Behavior
The app adapts UI and behavior based on device type:
- `Theme.isIPhone` vs `Theme.isIPadOrMac` for platform detection
- Different gradient fade heights for iPhone vs iPad/Mac
- Custom UITextView with touch-to-focus, shake-to-clear gestures
- Keyboard auto-appears on focus (iPhone), but requires tap on iPad/Mac

## Development Commands

### Build and Run
```bash
# Open in Xcode
open Cache.xcodeproj

# Build from command line (Scraps target)
xcodebuild -project Cache.xcodeproj -scheme Release -configuration Debug build

# Build release version
xcodebuild -project Cache.xcodeproj -scheme Release -configuration Release build
```

### Testing
```bash
# Run all tests (Cmd+U in Xcode)
xcodebuild -project Cache.xcodeproj -scheme Release -destination 'platform=iOS Simulator,name=iPhone 16' test

# Run UI tests specifically
xcodebuild -project Cache.xcodeproj -scheme Release -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:CacheUITests test
```

## File Organization

```
Cache/
├── App/
│   ├── ScrapsApp.swift       # App entry point, ScenePhase lifecycle handling
│   ├── Preferences.swift     # App-wide constants (time thresholds, etc.)
│   └── Theme.swift           # Colors, fonts, platform detection, styling
├── Managers/
│   ├── TextDocument.swift         # UIDocument subclass for iCloud sync
│   ├── DocumentManager.swift      # Multi-scrap manager, conflict resolution, lifecycle
│   └── TextHighlightManager.swift # NSLayoutManager for real-time syntax highlighting
├── Models/
│   └── Scrap.swift           # Data model with timestamp parsing/generation
├── Views/
│   ├── MainView.swift        # Root view with ScrollView + scraps list
│   ├── ScrapView.swift       # Individual scrap container (separator + editor + background)
│   ├── SeparatorView.swift   # Date separator between scraps
│   └── TextEditorView.swift  # UIViewRepresentable wrapper for EnhancedTextView
└── Assets.xcassets/
```

## Common Tasks

### Adding New Keyword Highlights
Edit the `HighlightPatterns` enum at the top of `TextHighlightManager.swift` (the
`keywordRegexes` array). Patterns are shared between the live editor and the
read-only archive preview (`ScrapPreviewView`). Use `\b` for word boundaries:
```swift
"\\byourword\\b"
```

### Changing Scrap Creation Threshold
Edit `Preferences.swift` - currently 5 minutes (300 seconds). This controls when a new scrap is auto-created after app returns from background.

### Adjusting Colors/Styling
Edit `Theme.swift` for:
- Text size, padding, spacing
- Highlight colors (light/dark mode)
- Cursor color
- Link styling
- Focus background color

### Modifying Scrap Filename Format
Edit `Scrap.swift`:
- `generateFilename()` - creates new filenames
- `parseTimestamp()` - parses existing filenames
- Current format: `scrap-YYYY-MM-DD-HHmmss.txt`

## Testing iCloud Sync

**Multi-device testing is critical** - iCloud sync issues only appear across devices:

1. Use simulator + physical device (or two simulators)
2. Test scenarios:
   - Edit on device A, switch to device B (should see changes)
   - Edit on both simultaneously (conflict resolution)
   - Edit offline, go online (delayed sync)
   - Kill app during edit (persistence)
   - Quit app (Cmd+Q on macOS) immediately after typing (ScenePhase test)

**Debugging sync:**
- macOS Console.app: filter by "bird" (iCloud daemon)
- Look for file coordination messages
- If no coordination messages appear → NSFileCoordinator not being used

## Important Implementation Notes

### Why No Debounced Saves?
The app saves immediately on every text change because:
- UIDocument.save() is already async (doesn't block typing)
- UIDocument internally coalesces rapid saves
- Prevents data loss when quitting quickly after editing
- Simpler code (no timer management or edge cases)

### Why ScenePhase instead of UIKit Notifications?
ScenePhase is used for lifecycle management because:
- Correctly handles macOS Cmd+Q (UIKit's `didEnterBackgroundNotification` doesn't fire)
- Consistent behavior across iOS, iPadOS, and macOS
- SwiftUI-native approach
- See `icloud-sync-best-practices.md:32-51` for details

### Focus Management
Focus behavior is complex due to auto-creation of scraps:
- `shouldSaveFocusChanges` flag prevents race conditions during initial load
- Focus is restored by **filename** (not UUID) because scraps may be deleted/recreated
- Auto-focus happens after scroll completes (0.2s delay) to avoid keyboard flicker

### Custom UITextView Behaviors
`EnhancedTextView` (in `TextEditorView.swift:114-178`) implements:
- Touch-to-focus (keyboard appears on first tap)
- Shake gesture detection (triggers clear confirmation)
- Custom cursor color matching app theme
- Auto-scroll to keep cursor visible during keyboard navigation

## Dependencies

- **SmoothGradient** (1.0.0) - Gradients without color banding for top/bottom fade effects
  - Used in `MainView.swift` for visual polish
  - Repo: https://github.com/raymondjavaxx/SmoothGradient

## Platform Support

- **iPhone**: All features, optimized for single-hand use
- **iPad**: Full support with larger text area
- **macOS** (Mac Catalyst): Full keyboard support, Cmd+Q handling via ScenePhase

## Known Patterns

### Line-Based Regex Processing
`TextHighlightManager` only processes edited lines, not the entire document:
```swift
let processRange = (text as NSString).lineRange(for: newCharRange)
```
This is critical for performance with long documents.

### Async Document Operations
All UIDocument operations are async - completion handlers are required:
```swift
document.save(to: url, for: .forOverwriting) { success in
    // Handle completion
}
```

### Conflict Resolution Strategy
Implements last-writer-wins (simplest strategy):
```swift
// See DocumentManager.swift:303-345 (conflict resolution at 306-334)
try NSFileVersion.removeOtherVersionsOfItem(at: url)
for version in conflictVersions {
    version.isResolved = true
}
```
