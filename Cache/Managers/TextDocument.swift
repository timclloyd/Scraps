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
            setSnapshot(text)
        }
    }

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
        Task { @MainActor in
            self.text = loadedText
        }
    }

    func updateText(_ newText: String) {
        text = newText
        updateChangeCount(.done)
    }
}
