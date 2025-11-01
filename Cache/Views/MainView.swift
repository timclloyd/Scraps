//
//  MainView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//
//  Root view for the app, managing text input state and coordinating UI components

import SwiftUI

struct MainView: View {
    @AppStorage("currentText") private var currentText = ""
    @State private var showingDeleteAlert = false
    
    var textSize: CGFloat = 16
    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 48
    
    var body: some View {
        GradientTextWrapper(
            text: $currentText,
            font: UIFont(name: Theme.font, size: textSize) ?? UIFont.systemFont(ofSize: textSize),
            padding: EdgeInsets(
                top: 0,
                leading: horizontalPadding,
                bottom: verticalPadding,
                trailing: horizontalPadding
            ),
            onShake: {
                showingDeleteAlert = true
            },
            topFadeHeight: 0,
            bottomFadeHeight: textSize * 3
        )
        .ignoresSafeArea(edges: .top)
        .alert("Clear the cache?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
            Button("Clear", role: .destructive) {
                currentText = ""
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } message: {
            Text("It's good to forget things sometimes")
        }
    }
}
