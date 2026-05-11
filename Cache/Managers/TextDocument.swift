import UIKit
import Combine
import os

@MainActor
class TextDocument: UIDocument, ObservableObject, @unchecked Sendable {
    var text: String = "" {
        willSet {
            objectWillChange.send()
        }
        didSet {
            // Keeps the nonisolated snapshot in lockstep with the main-actor text
            // property. contents(forType:) reads the snapshot without hopping actors,
            // so any keystroke (via updateText) must land in the snapshot before the
            // next autosave runs. Do not elide this — it is not redundant with the
            // load() path's own setSnapshot call.
            setSnapshot(text)
        }
    }

    private(set) var lastKnownSavedText: String?
    private(set) var mergeBaseText: String?
    private(set) var hasLocalEditsSinceMergeBase = false
    private(set) var localRevision = 0

    // Nonisolated snapshot read by contents(forType:) on whatever queue UIDocument chooses,
    // and written by load(fromContents:) before hopping back to the main actor. Avoids
    // DispatchQueue.main.sync which can deadlock with UIDocument's autosave machinery.
    private let snapshot = OSAllocatedUnfairLock<String>(initialState: "")

    nonisolated private func currentSnapshot() -> String {
        snapshot.withLock { $0 }
    }

    nonisolated private func setSnapshot(_ value: String) {
        snapshot.withLock { $0 = value }
    }

    nonisolated override func contents(forType typeName: String) throws -> Any {
        guard let data = currentSnapshot().data(using: .utf8) else {
            throw NSError(domain: "TextDocument", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode text as UTF-8"
            ])
        }
        return data
    }

    nonisolated override func load(fromContents contents: Any, ofType typeName: String?) throws {
        guard let data = contents as? Data else {
            throw NSError(domain: "TextDocument", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Contents is not Data"
            ])
        }

        guard let loadedText = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "TextDocument", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Failed to decode UTF-8 data"
            ])
        }

        setSnapshot(loadedText)
        // If load happens to run on the main thread (some UIDocument open paths do),
        // apply the UI-visible update synchronously so a user keystroke that happens
        // immediately after open cannot be clobbered by a deferred Task. assumeIsolated
        // is safe here — it asserts, it doesn't block like main.sync.
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                self.text = loadedText
                self.markLoadedTextAsSaved(loadedText)
            }
        } else {
            Task { @MainActor in
                self.text = loadedText
                self.markLoadedTextAsSaved(loadedText)
            }
        }
    }

    func updateText(_ newText: String) {
        guard text != newText else { return }
        if hasLocalEditsSinceMergeBase == false {
            mergeBaseText = lastKnownSavedText ?? text
            hasLocalEditsSinceMergeBase = true
        }
        localRevision += 1
        text = newText
        updateChangeCount(.done)
    }

    func markSaveSucceeded(text savedText: String, revision savedRevision: Int) {
        guard savedRevision == localRevision, text == savedText else { return }
        lastKnownSavedText = savedText
    }

    private func markLoadedTextAsSaved(_ loadedText: String) {
        guard documentState.contains(.inConflict) == false else { return }
        lastKnownSavedText = loadedText
        mergeBaseText = loadedText
        hasLocalEditsSinceMergeBase = false
        localRevision = 0
    }

    func markConflictResolutionCompleted() {
        lastKnownSavedText = text
        mergeBaseText = text
        hasLocalEditsSinceMergeBase = false
    }
}
