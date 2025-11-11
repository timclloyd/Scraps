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
                        // Simple separator for now (will be replaced with SeparatorView in Phase 3)
                        // Show separator BEFORE each scrap except the first one
                        if scrap.id != documentManager.scraps.first?.id {
                            HStack {
                                Text(scrap.timestamp, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("-")
                                    .foregroundColor(.gray)
                                Text(scrap.timestamp, style: .time)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Text("(\(scrap.filename))")
                                    .font(.caption2)
                                    .foregroundColor(.gray.opacity(0.5))
                                Spacer()
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.vertical, 8)
                            .background(Color.gray.opacity(0.1))
                        }

                        ScrapEditorView(
                            scrap: scrap,
                            document: scrap.document,
                            font: UIFont(name: Theme.font, size: textSize) ?? UIFont.systemFont(ofSize: textSize),
                            horizontalPadding: horizontalPadding,
                            verticalPadding: verticalPadding,
                            shouldBecomeFirstResponder: scrap.id == documentManager.scraps.last?.id && shouldFocusLatest
                        )
                        .id(scrap.id)
                    }
                }
                .padding(.top, Theme.isIPadOrMac ? verticalPadding / 2 : 0)
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

// Temporary scrap editor view for testing
struct ScrapEditorView: View {
    let scrap: Scrap
    @ObservedObject var document: TextDocument
    let font: UIFont
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let shouldBecomeFirstResponder: Bool

    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        UITextViewWrapper(
            text: Binding(
                get: { document.text },
                set: { newValue in
                    documentManager.textDidChange(for: scrap, newText: newValue)
                }
            ),
            font: font,
            padding: EdgeInsets(
                top: Theme.isIPadOrMac ? verticalPadding / 2 : 0,
                leading: Theme.isIPadOrMac ? verticalPadding / 2 : horizontalPadding,
                bottom: verticalPadding / 2,
                trailing: Theme.isIPadOrMac ? verticalPadding / 2 : horizontalPadding
            ),
            shouldBecomeFirstResponder: shouldBecomeFirstResponder
        )
    }
}
