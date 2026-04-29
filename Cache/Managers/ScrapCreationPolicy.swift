import Foundation
import UIKit

enum ScrapCreationPolicy {
    static func shouldCreateNewScrap(
        latestTimestamp: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard let latestTimestamp else { return false }
        return calendar.isDate(latestTimestamp, inSameDayAs: now) == false
    }

    static func isSafelyEmpty(text: String, documentState: UIDocument.State) -> Bool {
        guard !documentState.contains(.progressAvailable),
              !documentState.contains(.editingDisabled),
              !documentState.contains(.inConflict) else {
            return false
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
