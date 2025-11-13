# Scraps

A fast, minimal app for capturing thoughts and ideas in plain text. Syncs across iPhone, iPad, and Mac via iCloud.

> Used to be named Cache, hence the name of the project and some of the files.

## Features

- **Multi-document architecture** - each scrap is a separate timestamped text file
- **iCloud sync** - automatic sync across iOS, iPadOS, macOS devices using UIDocument
- **Minimal, distraction-free** text input
- **Auto-highlighting** for keywords (idea, fun, todo, remember, important, interesting, later)
- **Automatic URL detection** with tap support
- **Auto-datestamp separators** - visual timestamps between scraps
- **Auto scrap creation** - new scrap after 5 minutes of inactivity (similar to Drafts)

## Project Structure

```
Cache/
├── App/           # App entry point and theme configuration
├── Views/         # SwiftUI and UIKit view components
├── Managers/      # Business logic, sync, and text processing
├── Documentation/ # PRDs, code reviews, retros
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
- Each scrap is a separate `.txt` file: `scrap-YYYY-MM-DD-HHmmss.txt`
- Files are sorted chronologically (oldest first)
- New scrap auto-created after 5 minutes of inactivity

### UI Layer
- SwiftUI with custom UIKit components where needed
- Custom UITextView wrapper for enhanced text editing and gesture support

### Text Processing
- Custom NSLayoutManager for real-time syntax highlighting
- Efficient line-based regex processing (only processes changed content)
- Keyword highlighting: idea, fun, todo, remember, important, interesting, later

### Sync & Persistence
- UIDocument-based iCloud sync
- Last-writer-wins conflict resolution
- Offline support with local caching
