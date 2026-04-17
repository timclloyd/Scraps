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
            case .inactive:
                // .inactive fires for transient interruptions (Control Centre,
                // notification banners, incoming calls) — not termination. Fire
                // and forget; the .background case handles the flush barrier.
                documentManager.saveAllDocuments()
            case .background:
                // Hold the process alive until every UIDocument.save actually lands.
                // Without this, Cmd+Q on macOS or a fast termination on iOS can exit
                // before async saves flush, losing the last keystroke.
                //
                // On Mac Catalyst, beginBackgroundTask is effectively a no-op — AppKit
                // Cmd+Q bypasses the UIKit background-task API. The real guarantee on
                // macOS is that .background fires synchronously before exit, letting
                // us issue saves; UIDocument's file coordination then lands them.
                documentManager.beginBackgroundSaveBarrier()
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
