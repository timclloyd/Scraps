# Scraps

A super fast, minimal app for capturing thoughts and ideas in plain text. Syncs seamlessly across iPhone, iPad, and Mac via iCloud.

## Features

- **iCloud sync** - automatic sync across all your devices using UIDocument
- **Minimal, distraction-free** text input
- **Cross-platform** - iPhone, iPad, and macOS support with platform-optimized UI
- **Auto-highlighting** for keywords (idea, fun)
- **Automatic URL detection** with tap support
- **Shake to clear** with confirmation dialog
- **Automatic saving** with debounced writes (2s after typing stops)
- **Dark mode** support
- **Gradient fade effects** - smart top/bottom gradients that adapt to device type

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

- [SmoothGradient](https://github.com/raymondjavaxx/SmoothGradient) - High-quality gradient rendering for fade effects

### Running Tests

```bash
⌘U in Xcode or use xcodebuild test
```

## Architecture

### UI Layer
- SwiftUI with custom UIKit components where needed
- Custom UITextView wrapper for enhanced text editing and gesture support
- Platform-aware gradients and padding (Theme.swift)

### Text Processing
- Custom NSLayoutManager for real-time syntax highlighting
- Efficient line-based regex processing (only processes changed content)

### Sync & Persistence
- **UIDocument-based iCloud sync** for reliable cross-device synchronization
- Automatic NSFileCoordinator usage (required for iCloud daemon detection)
- Debounced saves to minimize disk I/O
- Last-writer-wins conflict resolution
- Offline support with local caching

See `icloud-sync-best-practices.md` for detailed sync implementation patterns.
