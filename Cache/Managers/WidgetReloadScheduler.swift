import Foundation
import WidgetKit

@MainActor
final class WidgetReloadScheduler {
    private static let widgetKinds = [
        "LatestScrapWidget",
        "HighlightSentimentWidget"
    ]

    private var workItem: DispatchWorkItem?

    func scheduleReload() {
        workItem?.cancel()
        let workItem = DispatchWorkItem {
            Self.reloadAllDataBackedWidgets()
        }
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func reloadImmediately() {
        Self.reloadAllDataBackedWidgets()
    }

    private static func reloadAllDataBackedWidgets() {
        for kind in widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
}
