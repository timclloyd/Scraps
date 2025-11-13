# Scraps

A super fast, minimal app for capturing thoughts and ideas in plain text. Syncs across iPhone, iPad, and Mac via iCloud.

> Used to be named Cache, hence the name of the project and some of the files.

## Features

- **Multi-document architecture** - each scrap is a separate timestamped text file
- **iCloud sync** - automatic sync across all devices using UIDocument
- **Minimal, distraction-free** text input
- **Cross-platform** - iPhone, iPad, and macOS with platform-optimized UI
- **Auto-highlighting** for keywords (idea, fun, todo, remember, important, interesting, later)
- **Automatic URL detection** with tap support
- **Auto-datestamp separators** - visual timestamps between scraps
- **Shake to clear** with confirmation dialog
- **Immediate automatic saving** - saves on every text change (UIDocument handles coalescing internally)
- **Dark mode** support
- **Gradient fade effects** - adaptive to device type
- **Smart scrap creation** - new scrap after 5 minutes of inactivity
- **Auto-cleanup** - empty scraps deleted automatically

## Project Structure

```
Cache/
├── App/           # App entry point and theme configuration
├── Views/         # SwiftUI and UIKit view components
├── Managers/      # Business logic, sync, and text processing
└── Assets.xcassets/
```

## Development

Built with SwiftUI and UIKit. Universal app supporting iPhone, iPad, and macOS (via Mac Catalyst).

### Dependencies

- [SmoothGradient](https://github.com/raymondjavaxx/SmoothGradient) - Gradients without colour banding

### Running Tests

```bash
⌘U in Xcode or use xcodebuild test
```

## Architecture

### Multi-Document Model
Unlike typical note apps with a single file, Scraps uses multiple text documents (one per scrap):
- Each scrap is a separate `.txt` file: `scrap-YYYY-MM-DD-HHmmss.txt`
- Files are sorted chronologically (oldest first)
- New scraps auto-created after 5 minutes of inactivity
- Empty scraps automatically deleted on backgrounding

### UI Layer
- SwiftUI with custom UIKit components where needed
- Custom UITextView wrapper for enhanced text editing and gesture support
- Platform-aware gradients and padding (Theme.swift)

### Text Processing
- Custom NSLayoutManager for real-time syntax highlighting
- Efficient line-based regex processing (only processes changed content)
- Keyword highlighting: idea, fun, todo, remember, important, interesting, later

### Sync & Persistence
- **UIDocument-based iCloud sync** for reliable cross-device synchronization
- **ScenePhase lifecycle management** for correct save timing (handles macOS Cmd+Q)
- **Immediate saves** on every text change (no debounce) - UIDocument coalesces internally
- Automatic NSFileCoordinator usage (required for iCloud daemon detection)
- Last-writer-wins conflict resolution
- Offline support with local caching

See `Documentation/icloud-sync-best-practices.md` for detailed sync implementation patterns.
