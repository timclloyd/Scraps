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
            activeSearchRange: activeSearchRange
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
