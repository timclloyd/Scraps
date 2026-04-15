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

    private var editorFont: UIFont {
        UIFont(name: Theme.font, size: Theme.textSize) ?? UIFont.systemFont(ofSize: Theme.textSize)
    }

    private var keyboardBackgroundColor: Color {
        viewMode == .latest ? Theme.latestPanelBackground : Theme.archiveBackground
    }

    private var activeMatch: (scrapID: String, range: NSRange)? {
        guard !searchMatches.isEmpty else { return nil }
        return searchMatches[currentMatchIndex]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                ZStack {
                    ArchiveListView(
                        keyboardHeight: keyboardTracker.height,
                        editorFont: editorFont,
                        searchQuery: searchQuery,
                        activeMatchScrapID: activeMatch?.scrapID,
                        activeMatchRange: activeMatch?.range
                    )

                    LatestScrapPanelView(keyboardHeight: keyboardTracker.height, viewMode: viewMode, editorFont: editorFont)
                        .offset(y: viewMode == .latest ? 0 : geometry.size.height)
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewMode)
                        .allowsHitTesting(viewMode == .latest)

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
                    .padding(.bottom, keyboardTracker.height)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
                .padding(.top, viewMode == .search ? 44 : 0)
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewMode == .search)
                .background(Theme.archiveBackground)

                // Search bar — sits at the ZStack's safe-area top, i.e. directly below the toolbar
                if viewMode == .search {
                    VStack(spacing: 0) {
                        SearchBarView(
                            query: $searchQuery,
                            matchCount: searchMatches.count,
                            currentMatchIndex: currentMatchIndex,
                            onPrev: prevMatch,
                            onNext: nextMatch
                        )
                        Spacer()
                    }
                    .transition(.opacity)
                }

                // Toolbar — higher z-order so it always wins hit tests, extends into status bar
                ToolbarView(
                    viewMode: viewMode,
                    topHeight: geometry.safeAreaInsets.top,
                    onToggleMode: toggleViewMode,
                    onToggleSearch: toggleSearch
                )
                .ignoresSafeArea(edges: .top)
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
            guard viewMode == .search else { return }
            clearSearch()
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                viewMode = .archive
            }
        }
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
            clearSearch()
            if priorMode == .archive {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewMode = .archive
                }
            } else {
                transitionToLatest()
            }
        case .latest, .archive:
            priorMode = viewMode
            dismissKeyboard()
            if viewMode == .latest { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                viewMode = .search
            }
        }
    }

    private func transitionToArchive() {
        dismissKeyboard()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            viewMode = .archive
        }
    }

    private func transitionToLatest() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            viewMode = .latest
        } completion: {
            documentManager.focusLatestScrap()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Search

    private func computeMatches(for query: String) -> [(scrapID: String, range: NSRange)] {
        guard !query.isEmpty else { return [] }
        var matches: [(String, NSRange)] = []
        for scrap in documentManager.scraps {
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
