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
                documentManager.focusedScrapID = scrapID
                documentManager.focusedScrapFilename = scrap.filename
                // Only save if initial load is complete (prevents auto-focus from overwriting saved filename)
                if documentManager.shouldSaveFocusChanges {
                    UserDefaults.standard.set(scrap.filename, forKey: "lastFocusedScrapFilename")
                }
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
