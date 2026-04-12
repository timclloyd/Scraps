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
    var onShake: (() -> Void)?

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
            onShake: onShake,
            onBecomeFocused: { scrapID in
                documentManager.focusedScrapID = scrapID
                documentManager.focusedScrapFilename = scrap.filename
                // Save focus only if initialization is complete
                if documentManager.isReady {
                    UserDefaults.standard.set(scrap.filename, forKey: "lastFocusedScrapFilename")
                }
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
