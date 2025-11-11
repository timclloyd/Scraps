//
//  MainView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//
//  Root view for the app, managing text input state and coordinating UI components

import SwiftUI

struct MainView: View {
    @EnvironmentObject var documentManager: DocumentManager
    @State private var shouldFocusLatest = false

    var textSize: CGFloat = Theme.textSize
    var horizontalPadding: CGFloat = Theme.horizontalPadding
    var verticalPadding: CGFloat = Theme.verticalPadding

    var body: some View {
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
            }
            .ignoresSafeArea(edges: .top)
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
    }
}
