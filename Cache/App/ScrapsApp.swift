//
//  CacheApp.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI
import UIKit

@main
struct ScrapsApp: App {
    @StateObject private var documentManager = DocumentManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(documentManager)
                .statusBarHidden()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background, .inactive:
                // Hold the process alive until every UIDocument.save actually lands.
                // Without this, Cmd+Q on macOS or a fast termination on iOS can exit
                // before async saves flush, losing the last keystroke.
                let app = UIApplication.shared
                var taskID: UIBackgroundTaskIdentifier = .invalid
                taskID = app.beginBackgroundTask(withName: "SaveAllScraps") {
                    if taskID != .invalid {
                        app.endBackgroundTask(taskID)
                        taskID = .invalid
                    }
                }
                documentManager.saveAllDocuments {
                    if taskID != .invalid {
                        app.endBackgroundTask(taskID)
                        taskID = .invalid
                    }
                }
                // Save timestamp for scrap creation logic
                documentManager.saveLastCloseTime()
            case .active:
                // Reset background flag for next cycle
                documentManager.resetBackgroundFlag()
                // Check for updates when app becomes active
                documentManager.checkForUpdates()
            @unknown default:
                break
            }
        }
    }
}
