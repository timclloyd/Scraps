//
//  MainView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//
//  Root view for the app, managing text input state and coordinating UI components

import SwiftUI
import SmoothGradient

struct MainView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @State private var isScrolledToTop = true
    @State private var keyboardHeight: CGFloat = 0
    @State private var keyboardObservers: [NSObjectProtocol] = []
    
    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(documentManager.scraps) { scrap in
                            VStack(spacing: 0) {
                                // Show datetime stamped separator before each scrap except the first one
                                if scrap.id != documentManager.scraps.first?.id {
                                    SeparatorView(timestamp: scrap.timestamp)
                                        .padding(.vertical, Theme.separatorVerticalPadding / 2 - Theme.horizontalPaddingBackground)
                                        .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
                                }

                                ScrapView(
                                    scrap: scrap,
                                    document: scrap.document,
                                    font: UIFont(name: Theme.font, size: Theme.textSize) ?? UIFont.systemFont(ofSize: Theme.textSize),
                                    isInitialFocus: scrap.id == documentManager.focusedScrapID
                                )
                                .padding(.horizontal, Theme.horizontalPadding - Theme.horizontalPaddingBackground)
                                .padding(.bottom, Theme.separatorVerticalPadding - Theme.horizontalPaddingBackground)
                            }
                            .background(
                                scrap.id == documentManager.focusedScrapID ?
                                    Color(uiColor: Theme.focusBackgroundColor(for: UITraitCollection.current)) :
                                    Color.clear
                            )
                            .cornerRadius(12)
                            .padding(.horizontal, Theme.horizontalPaddingBackground)
                            .id(scrap.id)
                            .padding(.top, Theme.textSize)
                        }
                    }
                    .padding(.top, Theme.isIPadOrMac ? Theme.verticalPadding / 2 : Theme.verticalPadding)
                    .padding(.bottom, Theme.textSize)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .scrollDismissesKeyboard(.never)
                .coordinateSpace(name: "scroll")
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    let newValue = offset >= 0
                    if isScrolledToTop != newValue {
                        isScrolledToTop = newValue
                    }
                }
                .onChange(of: documentManager.isReady) { wasReady, isNowReady in
                    // Scroll to last scrap once initialization is complete
                    if isNowReady, let lastScrap = documentManager.scraps.last {
                        proxy.scrollTo(lastScrap.id, anchor: .bottom)
                    }
                }
            }

            // Solid background at bottom to prevent text showing through keyboard
            VStack {
                Spacer()
                Color(uiColor: .systemBackground)
                    .frame(height: keyboardHeight)
            }
            .allowsHitTesting(false)
            .ignoresSafeArea(edges: .bottom)

            // Gradient overlays
            VStack(spacing: 0) {
                // Top fade prevents text from running into status bar/notch on iPad/Mac
                // iPhone doesn't need it when scrolled to top (notch provides natural spacing)
                SmoothLinearGradient(
                    from: Color(uiColor: .systemBackground).opacity(0.9),
                    to: Color(uiColor: .systemBackground).opacity(0),
                    startPoint: .top,
                    endPoint: .bottom,
                    curve: .easeOut
                )
                .frame(height: Theme.topFadeHeight)
                .opacity(Theme.isIPadOrMac ? 1 : (isScrolledToTop ? 0 : 1))
                .animation(.easeOut(duration: 0.2), value: isScrolledToTop)

                Spacer()

                // Bottom fade prevents text from running into home indicator area
                // Creates visual boundary for scrollable content
                SmoothLinearGradient(
                    from: Color(uiColor: .systemBackground).opacity(0),
                    to: Color(uiColor: .systemBackground).opacity(0.9),
                    startPoint: .top,
                    endPoint: .bottom,
                    curve: .easeIn
                )
                .frame(height: Theme.bottomFadeHeight)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            subscribeToKeyboardNotifications()
        }
        .onDisappear {
            unsubscribeFromKeyboardNotifications()
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

    // MARK: - Scroll Tracking

    // Preference key for tracking scroll offset
    struct ScrollOffsetPreferenceKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }
}
