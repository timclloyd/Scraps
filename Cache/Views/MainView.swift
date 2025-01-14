//
//  MainView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//
//  Root view for the app, managing text input state and coordinating UI components

import SwiftUI

struct MainView: View {
    @StateObject private var document = TextLineManager()
    @AppStorage("currentText") private var currentText = ""
    @FocusState private var isFocused: Bool
    @State private var showingDeleteAlert = false
    
    var textSize: CGFloat = 17
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 48
    
    var body: some View {
        VStack(spacing: 0) {
             UITextViewWrapper(
                text: $currentText,
                font: UIFont(name: "iAWriterQuattroS-Regular", size: textSize) ?? UIFont.systemFont(ofSize: textSize),
                padding: EdgeInsets(
                    top: textSize,
                    leading: horizontalPadding,
                    bottom: verticalPadding,
                    trailing: horizontalPadding
                ),
                onShake: {
                    // Show delete confirmation when shake is detected
                    showingDeleteAlert = true
                }
            )
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onChange(of: currentText) { oldValue, newValue in
                if !newValue.isEmpty {
                    document.addLine(newValue)
                }
            }
            .alert("Clear the cache?", isPresented: $showingDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
                Button("Clear", role: .destructive) {
                    currentText = ""
                    document.lines.removeAll()
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            } message: {
                Text("It's good to forget things sometimes")
            }
        }
    }
}
