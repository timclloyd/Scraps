//
//  ContentView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @StateObject private var document = NotesDocument()
    @State private var currentText = ""
    @FocusState private var isFocused: Bool
    
    var textSize: CGFloat = 16
    var horizontalPadding: CGFloat = 16
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(document.lines) { line in
                            Text(line.text)
                                .font(.custom("JetBrainsMono-Regular", size: textSize))
                                .foregroundColor(isToday(date: line.creationDate) ? .primary : .secondary)
                                .padding(.horizontal, horizontalPadding)
                        }
                        
                        TextField("", text: $currentText, axis: .vertical)
                            .font(.custom("JetBrainsMono-Regular", size: textSize))
                            .textFieldStyle(.plain)
                            .focused($isFocused)
                            .padding(.horizontal, horizontalPadding)
                            .id("textField")
                            .onSubmit {
                                if !currentText.isEmpty {
                                    document.addLine(currentText)
                                    currentText = ""
                                    
                                    // Scroll to bottom after a brief delay to ensure layout is updated
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        withAnimation {
                                            proxy.scrollTo("textField", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                    }
                }
            }
        }
        .onAppear {
            isFocused = true
        }
    }
    
    private func isToday(date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}
