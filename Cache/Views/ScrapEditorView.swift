//
//  ScrapEditorView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//
//  Editor view for a single scrap, wrapping UITextView for text input

import SwiftUI

struct ScrapEditorView: View {
    let scrap: Scrap
    @ObservedObject var document: TextDocument
    let font: UIFont
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
            shouldBecomeFirstResponder: shouldBecomeFirstResponder
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
