import Foundation
import os
import UIKit

@MainActor
final class DocumentSaveCoordinator {
    private let widgetReloadScheduler: WidgetReloadScheduler
    private var backgroundSaveTaskID: UIBackgroundTaskIdentifier = .invalid

    init(widgetReloadScheduler: WidgetReloadScheduler) {
        self.widgetReloadScheduler = widgetReloadScheduler
    }

    func saveDocument(_ scrap: Scrap) {
        scrap.document.save(to: scrap.document.fileURL, for: .forOverwriting) { [weak widgetReloadScheduler] success in
            if !success {
                print("Error: Failed to save scrap: \(scrap.filename)")
            } else {
                Task { @MainActor in
                    widgetReloadScheduler?.scheduleReload()
                }
            }
        }
    }

    func beginBackgroundSaveBarrier(for scraps: [Scrap]) {
        let app = UIApplication.shared
        if backgroundSaveTaskID != .invalid {
            app.endBackgroundTask(backgroundSaveTaskID)
            backgroundSaveTaskID = .invalid
        }
        backgroundSaveTaskID = app.beginBackgroundTask(withName: "SaveAllScraps") { [weak self] in
            guard let self else { return }
            if self.backgroundSaveTaskID != .invalid {
                app.endBackgroundTask(self.backgroundSaveTaskID)
                self.backgroundSaveTaskID = .invalid
            }
        }
        saveAllDocuments(scraps) { [weak self] in
            guard let self else { return }
            if self.backgroundSaveTaskID != .invalid {
                app.endBackgroundTask(self.backgroundSaveTaskID)
                self.backgroundSaveTaskID = .invalid
            }
        }
    }

    func saveAllDocuments(
        _ scraps: [Scrap],
        completion: (@MainActor @Sendable () -> Void)? = nil
    ) {
        guard !scraps.isEmpty else {
            completion?()
            return
        }

        let group = DispatchGroup()
        for scrap in scraps {
            group.enter()
            scrap.document.save(to: scrap.document.fileURL, for: .forOverwriting) { success in
                if !success {
                    print("Error: Failed to save scrap: \(scrap.filename)")
                }
                group.leave()
            }
        }

        let fired = OSAllocatedUnfairLock(initialState: false)
        let fire: @MainActor @Sendable () -> Void = { [weak widgetReloadScheduler] in
            let shouldRun = fired.withLock { already -> Bool in
                guard !already else { return false }
                already = true
                return true
            }
            if shouldRun {
                widgetReloadScheduler?.reloadImmediately()
                completion?()
            }
        }

        group.notify(queue: .main) {
            MainActor.assumeIsolated { fire() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            let wasStuck = fired.withLock { $0 == false }
            if wasStuck {
                print("Warning: saveAllDocuments watchdog fired after 20s — at least one save did not complete")
            }
            MainActor.assumeIsolated { fire() }
        }
    }
}
