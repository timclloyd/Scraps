//
//  CacheApp.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI

@main
struct ScrapsApp: App {
    @StateObject private var syncManager = CloudSyncManager()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(syncManager)
                .statusBarHidden()
        }
    }
}
