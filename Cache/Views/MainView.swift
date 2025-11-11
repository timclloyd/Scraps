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
    @State private var shouldFocusLatest = false
    @State private var isScrolledToTop = true
    @State private var keyboardHeight: CGFloat = 0

    var textSize: CGFloat = Theme.textSize
    var horizontalPadding: CGFloat = Theme.horizontalPadding
    var verticalPadding: CGFloat = Theme.verticalPadding
    var topFadeHeight: CGFloat = 48
    var bottomFadeHeight: CGFloat = 48
    
    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(documentManager.scraps) { scrap in
                            // Show datetime stamped separator before each scrap except the first one
                            if scrap.id != documentManager.scraps.first?.id {
                                SeparatorView(timestamp: scrap.timestamp)
                                    .padding(.bottom, Theme.separatorVerticalPadding / 2)
                            }
                            
                            ScrapView(
                                scrap: scrap,
                                document: scrap.document,
                                font: UIFont(name: Theme.font, size: textSize) ?? UIFont.systemFont(ofSize: textSize),
                                shouldBecomeFirstResponder: scrap.id == documentManager.scraps.last?.id && shouldFocusLatest
                            )
                            .id(scrap.id)
                            .padding(.bottom, Theme.separatorVerticalPadding)
                        }
                    }
                    .padding(.top, Theme.isIPadOrMac ? verticalPadding / 2 : verticalPadding)
                    .padding(.leading, Theme.horizontalPadding)
                    .padding(.trailing, Theme.horizontalPadding)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: ScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("scroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .ignoresSafeArea(edges: .top)
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    let newValue = offset >= 0
                    if isScrolledToTop != newValue {
                        isScrolledToTop = newValue
                    }
                }
                .onChange(of: documentManager.scraps.count) { oldCount, newCount in
                    // When scraps change, trigger focus
                    shouldFocusLatest = true
                    // Scroll to bottom
                    if let lastScrap = documentManager.scraps.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(lastScrap.id, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Focus latest scrap on initial load
                    shouldFocusLatest = true
                    if let lastScrap = documentManager.scraps.last {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo(lastScrap.id, anchor: .bottom)
                        }
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
                .frame(height: topFadeHeight)
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
                .frame(height: bottomFadeHeight)
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
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                keyboardHeight = keyboardFrame.height
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { _ in
            keyboardHeight = 0
        }
    }

    private func unsubscribeFromKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
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
