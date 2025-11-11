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

    @EnvironmentObject var documentManager: DocumentManager

    var body: some View {
        TextEditorView(
            text: Binding(
                get: { document.text },
                set: { newValue in
                    documentManager.textDidChange(for: scrap, newText: newValue)
                }
            ),
            font: font
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
