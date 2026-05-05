//
//  MainView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI
import SmoothGradient
import UIKit

private final class KeyboardTracker: ObservableObject {
    @Published var height: CGFloat = 0

    private var observers: [NSObjectProtocol] = []

    init() {
        let show = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                self?.height = frame.height
            }
        }
        let hide = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.height = 0
        }
        observers = [show, hide]
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }
}

enum ViewMode {
    case latest
    case archive
    case search
}

struct MainView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @State private var viewMode: ViewMode = .latest
    @State private var priorMode: ViewMode = .latest
    @StateObject private var keyboardTracker = KeyboardTracker()
    @State private var searchQuery: String = ""
    @State private var searchMatches: [(scrapID: String, range: NSRange)] = []
    @State private var currentMatchIndex: Int = 0
    @State private var latestFocusRequestID = 0
    @State private var showsPreferences = false

    private var editorFont: UIFont {
        Theme.uiFont(size: Theme.textSize)
    }

    private var keyboardBackgroundColor: Color {
        viewMode == .latest ? Theme.latestPanelBackground : Theme.archiveBackground
    }

    private func archiveBottomToolbarHeight(for geometry: GeometryProxy) -> CGFloat {
        viewMode == .archive ? geometry.safeAreaInsets.top : 0
    }

    private var activeMatch: (scrapID: String, range: NSRange)? {
        guard !searchMatches.isEmpty else { return nil }
        return searchMatches[currentMatchIndex]
    }

    private var latestScrapID: String? {
        documentManager.scraps.last?.id
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ZStack {
                    ArchiveListView(
                        keyboardHeight: keyboardTracker.height,
                        editorFont: editorFont,
                        viewMode: viewMode,
                        searchQuery: searchQuery,
                        activeMatchScrapID: activeMatch?.scrapID,
                        activeMatchRange: activeMatch?.range,
                        showsPreferences: $showsPreferences,
                        toolbarHeight: geometry.safeAreaInsets.top
                    )

                    LatestScrapPanelView(
                        keyboardHeight: keyboardTracker.height,
                        viewMode: viewMode,
                        editorFont: editorFont,
                        focusRequestID: latestFocusRequestID
                    )
                        .offset(y: viewMode == .latest ? 0 : geometry.size.height)
                        .allowsHitTesting(viewMode == .latest)

                    if !showsPreferences {
                        // Solid background behind keyboard to prevent text showing through
                        VStack {
                            Spacer()
                            keyboardBackgroundColor
                                .frame(height: keyboardTracker.height)
                        }
                        .allowsHitTesting(false)
                        .ignoresSafeArea(edges: .bottom)

                        // Bottom gradient — fades text above keyboard or screen bottom
                        VStack {
                            Spacer()
                            SmoothLinearGradient(
                                from: keyboardBackgroundColor.opacity(0),
                                to: keyboardBackgroundColor.opacity(0.9),
                                startPoint: .top, endPoint: .bottom, curve: .easeIn
                            )
                            .frame(height: Theme.bottomFadeHeight)
                        }
                        .padding(.bottom, keyboardTracker.height + archiveBottomToolbarHeight(for: geometry))
                        .ignoresSafeArea(edges: .bottom)
                        .allowsHitTesting(false)
                    }
                }
                .padding(.top, viewMode == .search ? 44 : 0)
                .background(Theme.archiveBackground)

                // Search bar — sits at the ZStack's safe-area top, i.e. directly below the toolbar
                if viewMode == .search {
                    VStack(spacing: 0) {
                        SearchBarView(
                            query: $searchQuery,
                            matchCount: searchMatches.count,
                            currentMatchIndex: currentMatchIndex,
                            onPrev: prevMatch,
                            onNext: nextMatch,
                            onDismiss: toggleSearch
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                        Spacer()
                    }
                }

                // Toolbar — higher z-order so it always wins hit tests, extends into status bar
                ToolbarView(
                    viewMode: viewMode,
                    topHeight: geometry.safeAreaInsets.top,
                    hidesButtons: showsPreferences,
                    onToggleMode: toggleViewMode,
                    onToggleSearch: toggleSearch
                )
                .ignoresSafeArea(edges: .top)

                if !documentManager.iCloudAvailable {
                    iCloudUnavailableOverlay
                }
            }
        }
        .background(Theme.archiveBackground)
        .ignoresSafeArea(edges: .bottom)
        .onChange(of: searchQuery) { _, query in
            let matches = computeMatches(for: query)
            searchMatches = matches
            currentMatchIndex = 0
        }
        .onChange(of: documentManager.focusedScrapID) { _, _ in
            if viewMode == .latest, documentManager.focusedScrapID == latestScrapID {
                requestLatestEditorFocus()
                return
            }

            guard viewMode == .search else { return }
            withAnimation(Theme.navigationOut) {
                viewMode = .archive
            } completion: {
                clearSearch()
            }
        }
        .onChange(of: latestScrapID) { _, latestID in
            guard viewMode == .latest,
                  latestID == documentManager.focusedScrapID else { return }
            requestLatestEditorFocus()
        }
        .onAppear {
            guard viewMode == .latest,
                  latestScrapID == documentManager.focusedScrapID else { return }
            requestLatestEditorFocus()
        }
    }

    // MARK: - iCloud status

    // Renders a full-screen explanatory overlay when the ubiquity container is
    // unavailable. Silent degradation here is indistinguishable from data loss —
    // the user must know why their scraps are missing and how to fix it.
    private var iCloudUnavailableOverlay: some View {
        ZStack {
            Theme.archiveBackground.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("iCloud unavailable")
                    .font(.headline)
                Text(iCloudUnavailableMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: openSettings) {
                    Text("Open Settings")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Theme.latestPanelBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(Theme.panelBorderColor), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        // Swallow taps so the editor underneath can't receive them while the
        // overlay is visible — otherwise invisible keystrokes reach UIDocument.
        .contentShape(Rectangle())
    }

    private var iCloudUnavailableMessage: String {
        #if targetEnvironment(macCatalyst)
        return "Scraps needs iCloud Drive to sync and save your notes. Sign in to iCloud and enable iCloud Drive for Scraps in System Settings."
        #else
        return "Scraps needs iCloud Drive to sync and save your notes. Sign in to iCloud and enable iCloud Drive for Scraps in Settings."
        #endif
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Navigation

    private func toggleViewMode() {
        switch viewMode {
        case .latest:
            transitionToArchive()
        case .archive:
            transitionToLatest()
        case .search:
            clearSearch()
            transitionToLatest()
        }
    }

    private func toggleSearch() {
        switch viewMode {
        case .search:
            dismissKeyboard()

            if priorMode == .archive {
                withAnimation(Theme.navigationOut) {
                    viewMode = .archive
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } completion: {
                    clearSearch()
                }
            } else {
                withAnimation(Theme.navigationIn) {
                    viewMode = .latest
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } completion: {
                    clearSearch()
                    documentManager.focusLatestScrap()
                    requestLatestEditorFocus()
                }
            }

        case .latest, .archive:
            priorMode = viewMode
            dismissKeyboard()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            withAnimation(Theme.navigationIn) {
                viewMode = .search
            }
        }
    }

    private func transitionToArchive() {
        dismissKeyboard()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Theme.navigationOut) {
            viewMode = .archive
        }
    }

    private func transitionToLatest() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(Theme.navigationIn) {
            viewMode = .latest
        } completion: {
            documentManager.focusLatestScrap()
            requestLatestEditorFocus()
        }
    }

    private func requestLatestEditorFocus() {
        latestFocusRequestID += 1
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Search

    private func computeMatches(for query: String) -> [(scrapID: String, range: NSRange)] {
        guard !query.isEmpty else { return [] }
        var matches: [(String, NSRange)] = []
        for scrap in documentManager.scraps.reversed() {
            let text = scrap.document.text as NSString
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.length > 0 {
                let range = text.range(of: query, options: .caseInsensitive, range: searchRange)
                guard range.location != NSNotFound else { break }
                matches.append((scrap.id, range))
                let next = range.upperBound
                searchRange = NSRange(location: next, length: text.length - next)
            }
        }
        return matches
    }

    private func nextMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + 1) % searchMatches.count
    }

    private func prevMatch() {
        guard !searchMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex - 1 + searchMatches.count) % searchMatches.count
    }

    private func clearSearch() {
        searchQuery = ""
        searchMatches = []
        currentMatchIndex = 0
    }
}
