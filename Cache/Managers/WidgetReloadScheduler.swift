import Foundation
import WidgetKit

@MainActor
final class WidgetReloadScheduler {
    private var workItem: DispatchWorkItem?

    func scheduleReload() {
        workItem?.cancel()
        let workItem = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: "LatestScrapWidget")
        }
        self.workItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: workItem)
    }

    func reloadImmediately() {
        WidgetCenter.shared.reloadTimelines(ofKind: "LatestScrapWidget")
    }
}
