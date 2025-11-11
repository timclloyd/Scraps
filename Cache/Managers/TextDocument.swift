import UIKit
import Combine

class TextDocument: UIDocument, ObservableObject {
    @Published var text: String = ""

    override func contents(forType typeName: String) throws -> Any {
        // Save text as UTF-8 data
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: "TextDocument", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode text as UTF-8"
            ])
        }
        return data
    }

    override func load(fromContents contents: Any, ofType typeName: String?) throws {
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

        text = loadedText
    }

    func updateText(_ newText: String) {
        text = newText
        updateChangeCount(.done)
    }
}
