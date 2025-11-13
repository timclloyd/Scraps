import UIKit
import Combine

@MainActor
class TextDocument: UIDocument, ObservableObject, @unchecked Sendable {
    var text: String = "" {
        willSet {
            objectWillChange.send()
        }
    }

    nonisolated override func contents(forType typeName: String) throws -> Any {
        // Save text as UTF-8 data
        // Access text - dispatch to main thread if needed
        let currentText: String
        if Thread.isMainThread {
            currentText = MainActor.assumeIsolated { text }
        } else {
            currentText = DispatchQueue.main.sync {
                MainActor.assumeIsolated { text }
            }
        }

        guard let data = currentText.data(using: .utf8) else {
            throw NSError(domain: "TextDocument", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode text as UTF-8"
            ])
        }
        return data
    }

    nonisolated override func load(fromContents contents: Any, ofType typeName: String?) throws {
        // Load text from UTF-8 data
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

        // Update text - dispatch to main thread if needed
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                text = loadedText
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    text = loadedText
                }
            }
        }
    }

    func updateText(_ newText: String) {
        text = newText
        updateChangeCount(.done)
    }
}
