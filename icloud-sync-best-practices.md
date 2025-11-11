# iCloud Sync Best Practices

A comprehensive guide to implementing reliable iCloud Document sync in iOS/macOS apps.

## Table of Contents

- [Overview](#overview)
  - [Lifecycle Management: ScenePhase vs UIKit Notifications](#lifecycle-management-scenephase-vs-uikit-notifications)
- [The Two Approaches](#the-two-approaches)
- [Save Timing Strategy: Debounce vs Immediate](#save-timing-strategy-debounce-vs-immediate)
- [UIDocument Pattern (Recommended)](#uidocument-pattern-recommended)
- [Critical Requirements](#critical-requirements)
- [Common Mistakes](#common-mistakes)
- [Testing & Debugging](#testing--debugging)
- [References](#references)

---

## Overview

### Why Proper Implementation Matters

iCloud sync can be unreliable if not implemented correctly. The most common issue is **missing NSFileCoordinator usage**, which causes the iCloud daemon to miss file changes entirely.

### Key Findings

- **Uploads are NOT automatic** without NSFileCoordinator
- **Downloads are NOT automatic** on iOS (must be explicitly triggered)
- **Background sync is not guaranteed** during app transitions
- **NSMetadataQuery notifications can be delayed** (several seconds is normal)

### Lifecycle Management: ScenePhase vs UIKit Notifications

**For SwiftUI apps, use `ScenePhase` instead of UIKit notifications:**

**Advantages of ScenePhase:**
- ✅ Handles all lifecycle events correctly on all platforms
- ✅ Catches macOS Cmd+Q (UIKit notifications miss this)
- ✅ SwiftUI-native approach
- ✅ Simpler, more declarative code
- ✅ Works consistently across iOS, iPadOS, and macOS

**UIKit Notifications limitations:**
- ❌ `didEnterBackgroundNotification` doesn't fire on macOS Cmd+Q
- ❌ Platform-specific behavior differences
- ❌ Requires manual observer setup/teardown

**When to use which:**
- **SwiftUI apps**: Always use ScenePhase
- **UIKit apps**: Use UIKit notifications (no ScenePhase available)
- **Mixed apps**: Prefer ScenePhase where possible

---

## The Two Approaches

### 1. UIDocument (Recommended)

**Pros:**
- Automatic NSFileCoordinator usage
- Built-in conflict resolution
- Handles document state changes
- Less code to maintain
- Apple's recommended approach

**Cons:**
- Slightly more overhead for simple text files
- Requires understanding of document lifecycle

**When to use:**
- Single document apps
- Document-based apps
- When you want Apple-standard behavior

### 2. Manual NSFileCoordinator + NSMetadataQuery

**Pros:**
- More control over sync timing
- Can be lighter weight

**Cons:**
- Must manually wrap ALL file I/O in NSFileCoordinator
- Must handle conflict resolution yourself
- More code to maintain
- Easy to get wrong

**When to use:**
- Multiple independent files
- Need granular control over sync behavior
- Already have complex file management

---

## Save Timing Strategy: Debounce vs Immediate

When implementing sync, you need to decide when to save changes to iCloud.

### Option 1: Immediate Saves (Recommended)

**Approach:** Save on every text change (or every meaningful change)

**Pros:**
- ✅ No data loss risk - changes saved immediately
- ✅ Simpler code - no timer management
- ✅ Works great with UIDocument (has internal coalescing)
- ✅ No edge cases with app termination

**Cons:**
- ⚠️ More frequent API calls (mitigated by UIDocument's internal optimization)
- ⚠️ Slightly higher battery usage (usually negligible)

**When to use:**
- Small files (like text documents)
- When using UIDocument (it handles efficiency internally)
- When data safety is critical
- Cross-platform apps where quit behavior varies

**Implementation:**
```swift
func textDidChange(_ newText: String) {
    text = newText
    saveDocument()  // UIDocument.save() is async
}
```

### Option 2: Debounced Saves

**Approach:** Wait N seconds after user stops typing before saving

**Pros:**
- ✅ Fewer explicit save calls
- ✅ May reduce battery usage slightly

**Cons:**
- ❌ Risk of data loss if user quits during debounce window
- ❌ More complex code (timer management)
- ❌ Need special handling for lifecycle events
- ❌ Edge cases: must invalidate timer on background/termination

**When to use:**
- Large files with expensive serialization
- High-frequency updates (like canvas drawing apps)
- When you're NOT using UIDocument (manual NSFileCoordinator)

**Implementation:**
```swift
private var saveTimer: Timer?

func textDidChange(_ newText: String) {
    text = newText

    saveTimer?.invalidate()
    saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
        self?.saveDocument()
    }
}

// CRITICAL: Must save immediately on lifecycle events
func saveBeforeBackground() {
    saveTimer?.invalidate()
    saveDocument()
}
```

### Recommendation

**Use immediate saves with UIDocument** - it's simpler and UIDocument already optimizes frequent saves internally. The added complexity and data loss risk of debouncing isn't worth the minimal performance gain for most apps.

---

## UIDocument Pattern (Recommended)

### Implementation Steps

#### 1. Create UIDocument Subclass

```swift
import UIKit

class TextDocument: UIDocument {
    var text: String = ""

    override func contents(forType typeName: String) throws -> Any {
        // Serialize to Data
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "TextDocument", code: 1)
        }
        return data
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
        // Deserialize from Data
        guard let data = contents as? Data,
              let loadedText = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TextDocument", code: 2)
        }
        text = loadedText
    }

    func updateText(_ newText: String) {
        text = newText
        updateChangeCount(.done)  // Marks document as dirty
    }
}
```

#### 2. Create Manager for SwiftUI Integration

```swift
import Foundation
import Combine
import UIKit

class DocumentManager: ObservableObject {
    @Published var text: String = ""

    private var document: TextDocument?
    private var isLoadingFromDocument = false

    private var documentURL: URL? {
        guard let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents/myfile.txt")
    }

    init() {
        setupLifecycleObservers()
        openDocument()
    }

    private func openDocument() {
        guard let url = documentURL else { return }

        document = TextDocument(fileURL: url)
        document?.open { [weak self] success in
            if success {
                self?.loadTextFromDocument()
                self?.setupDocumentStateObserver()
            }
        }
    }

    func textDidChange(_ newText: String) {
        guard !isLoadingFromDocument else { return }
        text = newText

        // Save immediately (async) - no debounce
        // UIDocument.save() is async so it won't block typing
        // UIDocument internally coalesces frequent saves for efficiency
        saveDocument()
    }

    private func saveDocument() {
        guard let document = document else { return }
        document.updateText(text)
        document.save(to: document.fileURL, for: .forOverwriting) { success in
            if !success {
                print("Failed to save document")
            }
        }
    }

    private func setupDocumentStateObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDocumentStateChanged),
            name: UIDocument.stateChangedNotification,
            object: document
        )
    }

    @objc private func handleDocumentStateChanged() {
        guard let document = document else { return }

        // Handle conflicts
        if document.documentState.contains(.inConflict) {
            resolveConflicts()
        }

        // Update UI if document changed externally
        if !document.documentState.contains(.editingDisabled) {
            loadTextFromDocument()
        }
    }

    private func resolveConflicts() {
        guard let document = document else { return }

        // Last-writer-wins strategy
        // IMPORTANT: UIDocument on iOS does NOT auto-resolve - you must do this manually
        do {
            let url = document.fileURL

            // Get conflict versions BEFORE removing (needed to mark them resolved)
            let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []

            // Remove all non-current versions from iCloud storage
            try NSFileVersion.removeOtherVersionsOfItem(at: url)

            // Mark ALL conflict versions as resolved (critical - prevents quota issues)
            for version in conflictVersions {
                version.isResolved = true
            }

            // Mark current version as resolved
            if let currentVersion = NSFileVersion.currentVersionOfItem(at: url) {
                currentVersion.isResolved = true
            }
        } catch {
            print("Error resolving conflict: \(error)")
        }
    }

    private func loadTextFromDocument() {
        guard let document = document else { return }
        isLoadingFromDocument = true
        DispatchQueue.main.async { [weak self] in
            self?.text = document.text
            self?.isLoadingFromDocument = false
        }
    }
}
```

#### 3. App Lifecycle Integration

```swift
import SwiftUI

@main
struct MyApp: App {
    @StateObject private var documentManager = DocumentManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentManager)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background, .inactive:
                // Save immediately when app backgrounds or becomes inactive
                // Critical for preventing data loss on quit (especially macOS Cmd+Q)
                documentManager.saveDocument()
            case .active:
                // Check for updates when app becomes active
                // Ensures user sees latest content from other devices
                documentManager.checkForUpdates()
            @unknown default:
                break
            }
        }
    }
}
```

#### 4. View Integration

```swift
struct ContentView: View {
    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        TextEditor(text: $documentManager.text)
            .onChange(of: documentManager.text) { _, newValue in
                documentManager.textDidChange(newValue)
            }
    }
}
```

---

## Critical Requirements

### 1. NSFileCoordinator is MANDATORY

**Why:**
- The iCloud daemon **only detects changes made through coordinated file operations**
- Direct file I/O bypasses the coordination system
- This is the #1 cause of unreliable sync

**With UIDocument:**
- ✅ Automatic - you don't need to do anything

**Without UIDocument (manual approach):**
```swift
// WRONG - iCloud may not detect this change
try text.write(to: url, atomically: true, encoding: .utf8)

// CORRECT - coordinated write
let coordinator = NSFileCoordinator(filePresenter: nil)
coordinator.coordinate(writingItemAt: url, options: .forReplacing) { coordinatedURL in
    try text.write(to: coordinatedURL, atomically: true, encoding: .utf8)
}
```

### 2. Check for Updates When App Becomes Active

**Why:**
- Background sync can be delayed or missed
- User may have made changes on another device
- Ensures fresh data when user switches back

**Implementation (SwiftUI - Recommended):**
```swift
// In your App struct, use ScenePhase
@Environment(\.scenePhase) private var scenePhase

var body: some Scene {
    WindowGroup {
        ContentView()
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
        if newPhase == .active {
            documentManager.checkForUpdates()
        }
    }
}
```

**Implementation (UIKit):**
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(checkForUpdates),
    name: UIApplication.didBecomeActiveNotification,
    object: nil
)

@objc private func checkForUpdates() {
    // With UIDocument: reload from document
    loadTextFromDocument()

    // With manual approach: query metadata and check modification dates
}
```

### 3. Save Before Background/Termination

**Why:**
- Background sync is not guaranteed
- App may be terminated without warning (especially macOS Cmd+Q)
- Prevents data loss when user quits quickly after editing

**Implementation (SwiftUI - Recommended):**
```swift
// In your App struct, use ScenePhase
@Environment(\.scenePhase) private var scenePhase

var body: some Scene {
    WindowGroup {
        ContentView()
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
        if newPhase == .background || newPhase == .inactive {
            documentManager.saveDocument()
        }
    }
}
```

**Note:** ScenePhase correctly handles all lifecycle events including:
- iOS: Home button press, app switcher
- macOS: Cmd+Q, window close
- iPadOS: Multitasking, app switching

**Implementation (UIKit):**
```swift
NotificationCenter.default.addObserver(
    self,
    selector: #selector(saveBeforeBackground),
    name: UIApplication.didEnterBackgroundNotification,
    object: nil
)

@objc private func saveBeforeBackground() {
    saveDocument()
}
```

**⚠️ UIKit Limitation:** `didEnterBackgroundNotification` doesn't fire on macOS Cmd+Q (termination vs backgrounding). Use ScenePhase for cross-platform apps.

### 4. Trigger Downloads on iOS

**Why:**
- iOS does NOT automatically download iCloud files (battery/bandwidth conservation)
- Files may exist as placeholders without content

**With UIDocument:**
- ✅ Handles this automatically during `open()`

**Without UIDocument:**
```swift
// Check if file needs downloading
if !FileManager.default.isUbiquitousItem(at: url) {
    try FileManager.default.startDownloadingUbiquitousItem(at: url)
}

// Wait for download before reading
// (need to monitor NSMetadataQuery for completion)
```

### 5. Handle Conflicts

**CRITICAL: UIDocument on iOS does NOT auto-resolve conflicts**
- On iOS: UIDocument only DETECTS conflicts via state changes - you must resolve them manually
- On macOS: NSDocument shows a UI sheet for user selection (more automatic)
- If you don't resolve: conflicts persist indefinitely and consume iCloud quota

**Strategy options:**
1. **Last-writer-wins** (simplest) - discard older versions
2. **User choice** - show UI to let user pick
3. **Merge** - attempt to merge changes (complex)

**With UIDocument (correct implementation):**
```swift
// Monitor document state
if document.documentState.contains(.inConflict) {
    let url = document.fileURL

    // IMPORTANT: Get conflict versions BEFORE removing
    let conflictVersions = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []

    // Remove all non-current versions
    try NSFileVersion.removeOtherVersionsOfItem(at: url)

    // Mark ALL conflict versions as resolved (prevents quota issues)
    for version in conflictVersions {
        version.isResolved = true
    }

    // Mark current version as resolved
    NSFileVersion.currentVersionOfItem(at: url)?.isResolved = true
}
```

---

## Common Mistakes

### ❌ Direct File I/O Without Coordination

```swift
// WRONG - iCloud daemon won't detect this
try text.write(to: cloudURL, atomically: true, encoding: .utf8)
```

**Fix:** Use UIDocument or wrap in NSFileCoordinator

### ❌ No Foreground Update Check

```swift
// App returns to foreground but doesn't check for updates
// User sees stale data
```

**Fix:** Add `didBecomeActiveNotification` observer

### ❌ Assuming Automatic Downloads

```swift
// WRONG - file may be a placeholder on iOS
let text = try String(contentsOf: cloudURL, encoding: .utf8)
```

**Fix:** Use UIDocument or trigger download explicitly

### ❌ Ignoring Document State

```swift
// Document state changed but UI not updated
// Conflicts not handled
```

**Fix:** Observe `UIDocument.stateChangedNotification`

### ❌ Persisting URLs

```swift
// WRONG - URLs can change
UserDefaults.standard.set(cloudURL, forKey: "documentURL")
```

**Fix:** Always use NSMetadataQuery to locate files, store filename only

---

## Testing & Debugging

### Multi-Device Testing

1. **Use multiple simulators OR real devices**
   - Simulator + physical device works well
   - iPad simulator + iPhone simulator
   - Mac + iPhone

2. **Test scenarios:**
   - Edit on device A, switch to device B
   - Edit on both devices simultaneously (conflict)
   - Edit offline, go online (delayed sync)
   - Kill app during edit (data persistence)

### Monitoring iCloud Daemon

**macOS Console.app:**
```
1. Open Console.app
2. Filter by "bird" (iCloud daemon process name)
3. Make changes in your app
4. Watch for coordination/sync messages
```

**Look for:**
- File coordination messages
- Upload/download activity
- Error messages about missing coordination

### Common Error Messages

**"Operation not permitted"**
- Missing iCloud entitlements
- Container identifier mismatch

**"File not found"**
- File not downloaded yet (iOS)
- Need to trigger download

**"No such file or directory"**
- Documents directory not created
- Check path construction

**No sync activity in Console**
- Not using NSFileCoordinator
- iCloud disabled in Settings

---

## References

### Apple Documentation

- [UIDocument Class Reference](https://developer.apple.com/documentation/uikit/uidocument)
- [NSFileCoordinator Class Reference](https://developer.apple.com/documentation/foundation/nsfilecoordinator)
- [NSMetadataQuery Class Reference](https://developer.apple.com/documentation/foundation/nsmetadataquery)
- [Designing for Documents in iCloud](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/Chapters/DesigningForDocumentsIniCloud.html)

### WWDC Sessions

- [WWDC 2012: iCloud Documents and Data](https://developer.apple.com/videos/play/wwdc2012/237/)
- [WWDC 2013: Using iCloud Documents and Data](https://developer.apple.com/videos/play/wwdc2013/219/)
- [WWDC 2014: Introducing CloudKit](https://developer.apple.com/videos/play/wwdc2014/208/)

### Key Concepts

- **NSFileCoordinator**: Coordinates file access between processes (required for iCloud)
- **NSMetadataQuery**: Discovers and monitors iCloud files
- **NSFilePresenter**: Receives notifications about file changes (used by UIDocument)
- **Ubiquity Container**: Special iCloud directory accessible via `url(forUbiquityContainerIdentifier:)`

### Developer Forums

- [Apple Developer Forums - iCloud](https://developer.apple.com/forums/tags/icloud)
- Common issues with delayed sync
- Platform-specific behaviors (iOS vs macOS)
- Debugging coordination problems

---

## Summary Checklist

When implementing iCloud sync:

- [ ] Use UIDocument if possible (handles most complexity automatically)
- [ ] If manual: wrap ALL file I/O in NSFileCoordinator blocks
- [ ] Check for updates on `didBecomeActiveNotification`
- [ ] Save before background/termination
- [ ] Handle conflicts (at minimum: last-writer-wins)
- [ ] Monitor document state changes
- [ ] Test on multiple devices
- [ ] Use Console.app to verify coordination is happening
- [ ] Never persist URLs (use NSMetadataQuery to locate files)
- [ ] Handle missing iCloud gracefully (signed out, disabled)

---

## Example: This Project

See `Cache/Managers/TextDocument.swift` and `Cache/Managers/DocumentManager.swift` for a complete working implementation using UIDocument with SwiftUI.

**Key features:**
- Automatic file coordination via UIDocument
- Immediate async saves on every edit (no debounce - UIDocument handles coalescing internally)
- SwiftUI ScenePhase for reliable lifecycle handling across all platforms
- Foreground update checking when app becomes active
- Last-writer-wins conflict resolution
- SwiftUI integration via `@Published` property
- Migration from old storage format

**Why no debouncing?**
- UIDocument.save() is already async (doesn't block typing)
- UIDocument internally coalesces rapid saves for efficiency
- Immediate saves prevent data loss when quitting quickly after editing
- Simpler code with fewer edge cases
