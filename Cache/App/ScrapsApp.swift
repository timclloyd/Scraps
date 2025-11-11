//
//  CacheApp.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI

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
                // Save immediately when app backgrounds or becomes inactive
                documentManager.saveDocument()
            case .active:
                // Check for updates when app becomes active
                documentManager.checkForUpdates()
            @unknown default:
                break
            }
        }
    }
}
