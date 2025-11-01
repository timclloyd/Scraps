//
//  CacheApp.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI

@main
struct ScrapsApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
                .statusBarHidden()
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    UserDefaults.standard.synchronize()
                }
        }
    }
}
