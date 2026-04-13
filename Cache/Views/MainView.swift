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

    @EnvironmentObject var documentManager: DocumentManager
    @State private var viewMode: ViewMode = .latest
    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardObservers: [NSObjectProtocol] = []

    private var editorFont: UIFont {
        UIFont(name: Theme.font, size: Theme.textSize) ?? UIFont.systemFont(ofSize: Theme.textSize)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Content — starts at y=safeAreaInsets.top naturally since the GeometryReader
                // is safe-area constrained (no ignoresSafeArea on the GR)
                ZStack {
                    archiveView()

                    latestScrapPanel()
                        .offset(y: viewMode == .latest ? 0 : geometry.size.height)
                        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: viewMode)
                        .allowsHitTesting(viewMode == .latest)

                    // Solid background behind keyboard to prevent text showing through
                    VStack {
                        Spacer()
                        Color(uiColor: .systemBackground)
                            .frame(height: keyboardHeight)
                    }
                    .allowsHitTesting(false)
                    .ignoresSafeArea(edges: .bottom)

                    // Bottom gradient — fades text above keyboard or screen bottom
                    VStack {
                        Spacer()
                        SmoothLinearGradient(
                            from: Color(uiColor: .systemBackground).opacity(0),
                            to: Color(uiColor: .systemBackground).opacity(0.9),
                            startPoint: .top, endPoint: .bottom, curve: .easeIn
                        )
                        .frame(height: Theme.bottomFadeHeight)
                    }
                    .padding(.bottom, keyboardHeight)
                    .ignoresSafeArea(edges: .bottom)
                    .allowsHitTesting(false)
                }
                .padding(.top, Theme.horizontalPaddingBackground)

                // Toolbar — higher z-order so it always wins hit tests, extends into status bar
                toolbarView(topHeight: geometry.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            subscribeToKeyboardNotifications()
        }
        .onDisappear {
            unsubscribeFromKeyboardNotifications()
        }
    }

    // MARK: - Subviews

    private func toolbarView(topHeight: CGFloat) -> some View {
        HStack {
            modeToggleButton
            Spacer()
        }
        .frame(height: topHeight)
        .padding(.horizontal, Theme.horizontalPadding)
        .background(Color(uiColor: .systemBackground))
    }

    private func latestScrapPanel() -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: Preferences.latestPanelCornerRadius,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: Preferences.latestPanelCornerRadius
        )

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    if let latestScrap = documentManager.scraps.last {
                        scrapCard(
                            scrap: latestScrap,
                            showsSeparator: false,
                            autoFocus: latestScrap.id == documentManager.focusedScrapID && viewMode == .latest,
                            showsFocusBackground: false,
                            topPadding: 12
                        )
                    }
                }
                .padding(.bottom, Theme.textSize)
            }
            .scrollDismissesKeyboard(.never)
            .background(Color(uiColor: .systemBackground))
            .clipShape(shape)
            .overlay(alignment: .top) {
                SmoothLinearGradient(
                    from: Color(uiColor: .systemBackground).opacity(0.9),
                    to: Color(uiColor: .systemBackground).opacity(0),
                    startPoint: .top, endPoint: .bottom, curve: .easeOut
                )
                .frame(height: Theme.topFadeHeight)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
            .ignoresSafeArea(.keyboard)
        }
        .overlay(alignment: .top) {
            shape.strokeBorder(Color(uiColor: .separator), lineWidth: 1)
        }
    }

    private func archiveView() -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(documentManager.scraps) { scrap in
                        scrapCard(
                            scrap: scrap,
                            showsSeparator: scrap.id != documentManager.scraps.first?.id,
                            autoFocus: false,
                            showsFocusBackground: true
                        )
                    }
                }
                .padding(.top, Theme.verticalPadding)
                .padding(.bottom, Theme.textSize)
            }
            .scrollDismissesKeyboard(.never)
            .contentMargins(.bottom, keyboardHeight, for: .scrollContent)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                SmoothLinearGradient(
                    from: Color(uiColor: .systemBackground).opacity(0.9),
                    to: Color(uiColor: .systemBackground).opacity(0),
                    startPoint: .top, endPoint: .bottom, curve: .easeOut
                )
                .frame(height: Theme.topFadeHeight)
                .allowsHitTesting(false)
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
        topPadding: CGFloat = Theme.textSize
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
                isInitialFocus: autoFocus
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
        .padding(.top, topPadding)
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
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            viewMode = .archive
        }
    }

    private func transitionToLatest() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            viewMode = .latest
        } completion: {
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

}
