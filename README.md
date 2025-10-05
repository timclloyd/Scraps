# Cache

A super fast, minimal iOS app for capturing thoughts and ideas in plain text.

## Features

- Minimal, distraction-free text input
- Auto-highlighting for keywords (idea, fun)
- Automatic URL detection with tap support
- Shake to clear with confirmation dialog
- Persistent storage with automatic saving
- Dark mode support
- Custom gradient fade effects

## Project Structure

```
Cache/
├── App/           # App entry point and theme configuration
├── Views/         # SwiftUI and UIKit view components
├── Managers/      # Business logic and text processing
├── Models/        # Data models
└── Assets.xcassets/
```

## Development

Built with SwiftUI and UIKit for iOS.

### Running Tests

```bash
⌘U in Xcode or use xcodebuild test
```

## Architecture

- MVVM pattern with `TextLineManager` as the main manager
- Custom UITextView wrapper for enhanced text editing
- Custom NSLayoutManager for real-time syntax highlighting
