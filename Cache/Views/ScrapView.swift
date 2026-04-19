//
//  ScrapView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//
//  View for displaying and editing a single scrap

import SwiftUI

struct ScrapView: View {
    let scrap: Scrap
    @ObservedObject var document: TextDocument
    let font: UIFont
    var isInitialFocus: Bool = false
    var searchQuery: String = ""
    var activeSearchRange: NSRange? = nil

    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        TextEditorView(
            text: Binding(
                get: { document.text },
                set: { newValue in
                    documentManager.textDidChange(for: scrap, newText: newValue)
                }
            ),
            font: font,
            isInitialFocus: isInitialFocus,
            scrapID: scrap.id,
            onBecomeFocused: { scrapID in
                documentManager.setFocusedScrap(id: scrapID, filename: scrap.filename)
            },
            searchQuery: searchQuery,
            activeSearchRange: activeSearchRange,
            initialTapLocation: consumePendingTapLocation()
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Consumes the pending tap point (set by `ScrapPreviewView.onTapGesture`) if it
    // belongs to this scrap, so re-evaluations of `ScrapView.body` don't replay the
    // same caret placement on every SwiftUI update.
    private func consumePendingTapLocation() -> CGPoint? {
        guard documentManager.focusedScrapID == scrap.id,
              let point = documentManager.pendingFocusTapLocation else { return nil }
        documentManager.pendingFocusTapLocation = nil
        return point
    }
}
