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
    @State private var showingDeleteAlert = false

    var textSize: CGFloat = Theme.textSize
    var horizontalPadding: CGFloat = Theme.horizontalPadding
    var verticalPadding: CGFloat = Theme.verticalPadding
    
    var body: some View {
        GradientTextWrapper(
            text: $documentManager.text,
            font: UIFont(name: Theme.font, size: textSize) ?? UIFont.systemFont(ofSize: textSize),
            padding: EdgeInsets(
                top: Theme.isIPadOrMac ? verticalPadding / 2 : 0,
                leading: Theme.isIPadOrMac ? verticalPadding / 2 : horizontalPadding,
                bottom: verticalPadding,
                trailing: Theme.isIPadOrMac ? verticalPadding / 2 : horizontalPadding,
            ),
            onShake: {
                showingDeleteAlert = true
            },
            topFadeHeight: Theme.isIPadOrMac ? textSize * 3 : 0,
            bottomFadeHeight: textSize * 3
        )
        .onChange(of: documentManager.text) { oldValue, newValue in
            documentManager.textDidChange(newValue)
        }
        .ignoresSafeArea(edges: .top)
        .alert("Discard all scraps?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
            Button("Clear", role: .destructive) {
                documentManager.text = ""
                documentManager.textDidChange("")
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } message: {
            Text("It's good to forget things sometimes")
        }
    }
}
