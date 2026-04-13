//
//  MainView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//
//  Root view for the app, managing text input state and coordinating UI components

import SwiftUI
import SmoothGradient
import UIKit

struct MainView: View {
    private enum ViewMode {
        case latest
        case archive
    }

    private let latestTransition = AnyTransition.move(edge: .bottom)
    private let archiveTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .top),
        removal: .offset(CGSize(width: 0, height: -(UIScreen.main.bounds.height + 200)))
    )

    private struct ScrollMetrics: Equatable {
        let minY: CGFloat
        let maxY: CGFloat
        let height: CGFloat

        static let zero = ScrollMetrics(minY: 0, maxY: 0, height: 0)
    }

    @EnvironmentObject var documentManager: DocumentManager
    @State private var viewMode: ViewMode = .latest
    @State private var isScrolledToTop = true
    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardObservers: [NSObjectProtocol] = []
    @State private var latestOverscroll: CGFloat = 0
    @State private var archiveBottomOverscroll: CGFloat = 0

    private var editorFont: UIFont {
        UIFont(name: Theme.font, size: Theme.textSize) ?? UIFont.systemFont(ofSize: Theme.textSize)
    }

    private var overscrollActivationHeight: CGFloat {
        editorFont.lineHeight * Preferences.archiveRevealLineCount
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Group {
                    switch viewMode {
                    case .latest:
                        latestScrapView(viewportHeight: geometry.size.height)
                            .transition(latestTransition)
                    case .archive:
                        archiveView(viewportHeight: geometry.size.height)
                            .transition(archiveTransition)
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewMode)

                VStack {
                    HStack {
                        modeToggleButton
                        Spacer()
                    }
                    .padding(.horizontal, Theme.horizontalPadding)
                    .padding(.top, Theme.isIPadOrMac ? Theme.verticalPadding / 3 : Theme.verticalPadding / 2)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)

                VStack {
                    if viewMode == .latest {
                        revealBox(height: latestOverscroll, edge: .top)
                        Spacer()
                    } else {
                        Spacer()
                        revealBox(height: archiveBottomOverscroll, edge: .bottom)
                    }
                }
                .allowsHitTesting(false)

                // Solid background at bottom to prevent text showing through keyboard
                VStack {
                    Spacer()
                    Color(uiColor: .systemBackground)
                        .frame(height: keyboardHeight)
                }
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .bottom)

                // Top gradient — fades text behind the status bar area.
                // ignoresSafeArea(.top) ensures it covers the status bar, matching
                // the scroll views which also extend behind the status bar.
                VStack {
                    SmoothLinearGradient(
                        from: Color(uiColor: .systemBackground).opacity(0.9),
                        to: Color(uiColor: .systemBackground).opacity(0),
                        startPoint: .top,
                        endPoint: .bottom,
                        curve: .easeOut
                    )
                    .frame(height: Theme.topFadeHeight)
                    .opacity(1)
                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

                // Bottom gradient — fades text at the screen bottom or above the keyboard.
                // ignoresSafeArea(.bottom) extends to the physical screen edge so the
                // keyboard padding (which includes the safe area) positions it correctly.
                VStack {
                    Spacer()
                    SmoothLinearGradient(
                        from: Color(uiColor: .systemBackground).opacity(0),
                        to: Color(uiColor: .systemBackground).opacity(0.9),
                        startPoint: .top,
                        endPoint: .bottom,
                        curve: .easeIn
                    )
                    .frame(height: Theme.bottomFadeHeight)
                }
                .padding(.bottom, keyboardHeight)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            subscribeToKeyboardNotifications()
        }
        .onDisappear {
            unsubscribeFromKeyboardNotifications()
        }
    }

    private func latestScrapView(viewportHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let latestScrap = documentManager.scraps.last {
                        scrapCard(
                            scrap: latestScrap,
                            showsSeparator: false,
                            autoFocus: latestScrap.id == documentManager.focusedScrapID,
                            showsFocusBackground: false,
                            onShake: handleShake
                        )
                    }
                }
                .padding(.top, Theme.isIPadOrMac ? Theme.verticalPadding / 2 : Theme.verticalPadding)
                .padding(.bottom, Theme.textSize)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: LatestScrollMetricsPreferenceKey.self,
                            value: ScrollMetrics(
                                minY: geometry.frame(in: .named("latestScroll")).minY,
                                maxY: geometry.frame(in: .named("latestScroll")).maxY,
                                height: geometry.size.height
                            )
                        )
                    }
                )
            }
            .scrollDismissesKeyboard(.never)
            .coordinateSpace(name: "latestScroll")
            .ignoresSafeArea(edges: .top)
            .simultaneousGesture(
                DragGesture().onEnded { _ in
                    guard latestOverscroll >= overscrollActivationHeight else { return }
                    transitionToArchive()
                }
            )
            .onPreferenceChange(LatestScrollMetricsPreferenceKey.self) { metrics in
                latestOverscroll = max(0, metrics.minY)
                isScrolledToTop = metrics.minY >= 0
            }
            .onAppear {
                scrollToLatestScrap(using: proxy)
            }
            .onChange(of: documentManager.isReady) { _, isNowReady in
                if isNowReady {
                    scrollToLatestScrap(using: proxy)
                }
            }
            .onChange(of: documentManager.focusedScrapID) { _, _ in
                scrollToLatestScrap(using: proxy)
            }
            .onChange(of: documentManager.scraps.count) { _, _ in
                scrollToLatestScrap(using: proxy)
            }
        }
    }

    private func archiveView(viewportHeight: CGFloat) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(documentManager.scraps) { scrap in
                        scrapCard(
                            scrap: scrap,
                            showsSeparator: scrap.id != documentManager.scraps.first?.id,
                            autoFocus: false,
                            showsFocusBackground: true,
                            onShake: handleShake
                        )
                    }
                }
                .padding(.top, Theme.isIPadOrMac ? Theme.verticalPadding / 2 : Theme.verticalPadding)
                .padding(.bottom, Theme.textSize)
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: ArchiveScrollMetricsPreferenceKey.self,
                            value: ScrollMetrics(
                                minY: geometry.frame(in: .named("archiveScroll")).minY,
                                maxY: geometry.frame(in: .named("archiveScroll")).maxY,
                                height: geometry.size.height
                            )
                        )
                    }
                )
            }
            .scrollDismissesKeyboard(.never)
            .coordinateSpace(name: "archiveScroll")
            .ignoresSafeArea(edges: .top)
            .simultaneousGesture(
                DragGesture().onEnded { _ in
                    guard archiveBottomOverscroll >= overscrollActivationHeight else { return }
                    transitionToLatest()
                }
            )
            .onPreferenceChange(ArchiveScrollMetricsPreferenceKey.self) { metrics in
                let naturalBottomGap = max(0, viewportHeight - metrics.height)
                archiveBottomOverscroll = max(0, viewportHeight - metrics.maxY - naturalBottomGap)
                isScrolledToTop = metrics.minY >= 0
            }
            .onAppear {
                scrollToLatestScrap(using: proxy)
            }
            .onChange(of: documentManager.scraps.count) { _, _ in
                scrollToLatestScrap(using: proxy)
            }
        }
    }

    private func scrapCard(
        scrap: Scrap,
        showsSeparator: Bool,
        autoFocus: Bool,
        showsFocusBackground: Bool,
        onShake: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 0) {
            if showsSeparator {
                SeparatorView(timestamp: scrap.timestamp)
                    .padding(.vertical, Theme.separatorVerticalPadding / 2 - Theme.horizontalPaddingBackground)
                    .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
            }

            ScrapView(
                scrap: scrap,
                document: scrap.document,
                font: editorFont,
                isInitialFocus: autoFocus,
                onShake: onShake
            )
            .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
            .padding(.bottom, Theme.separatorVerticalPadding - Theme.horizontalPaddingBackground)
        }
        .background(
            showsFocusBackground && scrap.id == documentManager.focusedScrapID ?
                Color(uiColor: Theme.focusBackgroundColor(for: UITraitCollection.current)) :
                Color.clear
        )
        .cornerRadius(12)
        .padding(.horizontal, Theme.horizontalPaddingBackground)
        .id(scrap.id)
        .padding(.top, Theme.textSize)
    }

    private func revealBox(height: CGFloat, edge: VerticalEdge) -> some View {
        let clampedHeight = min(max(0, height), overscrollActivationHeight)
        return Color.red
            .opacity(clampedHeight >= overscrollActivationHeight ? 0.95 : 0.8)
            .frame(maxWidth: .infinity)
            .frame(height: clampedHeight)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: clampedHeight)
            .ignoresSafeArea(edges: edge == .top ? .top : .bottom)
    }

    private func handleShake() {
        Task {
            let newScrap = await documentManager.createNewScrapOnDemand()
            guard newScrap != nil else { return }

            await MainActor.run {
                latestOverscroll = 0
                archiveBottomOverscroll = 0
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                    viewMode = .latest
                }
            }
        }
    }

    private var modeToggleButton: some View {
        Button(action: toggleViewMode) {
            Text(viewMode == .latest ? "Archive" : "Latest")
                .font(.custom(Theme.font, size: Theme.separatorFontSize))
                .foregroundColor(Color(uiColor: .white))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.9))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleViewMode() {
        switch viewMode {
        case .latest:
            transitionToArchive()
        case .archive:
            transitionToLatest()
        }
    }

    private func transitionToArchive() {
        dismissKeyboard()
        latestOverscroll = 0
        archiveBottomOverscroll = 0

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            viewMode = .archive
        }
    }

    private func transitionToLatest() {
        latestOverscroll = 0
        archiveBottomOverscroll = 0

        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            viewMode = .latest
        }

        DispatchQueue.main.async {
            documentManager.focusLatestScrap()
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func scrollToLatestScrap(using proxy: ScrollViewProxy) {
        guard let latestScrap = documentManager.scraps.last else { return }

        DispatchQueue.main.async {
            proxy.scrollTo(latestScrap.id, anchor: .bottom)
        }
    }

    // MARK: - Keyboard Tracking

    private func subscribeToKeyboardNotifications() {
        unsubscribeFromKeyboardNotifications()

        let showObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
            }
        }

        let hideObserver = NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            keyboardHeight = 0
        }

        keyboardObservers = [showObserver, hideObserver]
    }

    private func unsubscribeFromKeyboardNotifications() {
        for observer in keyboardObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        keyboardObservers.removeAll()
    }

    private struct LatestScrollMetricsPreferenceKey: PreferenceKey {
        static var defaultValue = ScrollMetrics.zero

        static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
            value = nextValue()
        }
    }

    private struct ArchiveScrollMetricsPreferenceKey: PreferenceKey {
        static var defaultValue = ScrollMetrics.zero

        static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
            value = nextValue()
        }
    }
}
