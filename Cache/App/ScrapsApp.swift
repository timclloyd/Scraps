//
//  CacheApp.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI
import UIKit

extension Notification.Name {
    static let scrapsToggleSearch = Notification.Name("scrapsToggleSearch")
    static let scrapsToggleViewMode = Notification.Name("scrapsToggleViewMode")
    static let scrapsShowPreferences = Notification.Name("scrapsShowPreferences")
    static let scrapsDismissPresentedUI = Notification.Name("scrapsDismissPresentedUI")
    static let scrapsPreviousSearchMatch = Notification.Name("scrapsPreviousSearchMatch")
    static let scrapsNextSearchMatch = Notification.Name("scrapsNextSearchMatch")
    static let scrapsOpenRandomArchiveScrap = Notification.Name("scrapsOpenRandomArchiveScrap")
    static let scrapsScrollArchiveToTop = Notification.Name("scrapsScrollArchiveToTop")
    static let scrapsScrollArchiveToBottom = Notification.Name("scrapsScrollArchiveToBottom")
}

private struct ScrapsViewModeFocusedValueKey: FocusedValueKey {
    typealias Value = ViewMode
}

extension FocusedValues {
    var scrapsViewMode: ViewMode? {
        get { self[ScrapsViewModeFocusedValueKey.self] }
        set { self[ScrapsViewModeFocusedValueKey.self] = newValue }
    }
}

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
        .commands {
            ScrapsCommands()
        }
    }
}

private struct ScrapsCommands: Commands {
    @FocusedValue(\.scrapsViewMode) private var viewMode

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Button("Search") {
                NotificationCenter.default.post(name: .scrapsToggleSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Toggle View") {
                NotificationCenter.default.post(name: .scrapsToggleViewMode, object: nil)
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Random Scrap") {
                NotificationCenter.default.post(name: .scrapsOpenRandomArchiveScrap, object: nil)
            }
            .keyboardShortcut("r", modifiers: .command)

            Button("Previous Match") {
                NotificationCenter.default.post(name: .scrapsPreviousSearchMatch, object: nil)
            }
            .keyboardShortcut(.leftArrow, modifiers: .command)
            .disabled(viewMode != .search)

            Button("Next Match") {
                NotificationCenter.default.post(name: .scrapsNextSearchMatch, object: nil)
            }
            .keyboardShortcut(.rightArrow, modifiers: .command)
            .disabled(viewMode != .search)

            Button("Archive Top") {
                NotificationCenter.default.post(name: .scrapsScrollArchiveToTop, object: nil)
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(viewMode != .archive)

            Button("Archive Bottom") {
                NotificationCenter.default.post(name: .scrapsScrollArchiveToBottom, object: nil)
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(viewMode != .archive)

            Button("Close") {
                NotificationCenter.default.post(name: .scrapsDismissPresentedUI, object: nil)
            }
            .keyboardShortcut(.escape, modifiers: [])
        }

        CommandGroup(replacing: .appSettings) {
            Button("Preferences") {
                NotificationCenter.default.post(name: .scrapsShowPreferences, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
