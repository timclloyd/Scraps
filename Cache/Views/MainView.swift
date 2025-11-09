//
//  MainView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//
//  Root view for the app, managing text input state and coordinating UI components

import SwiftUI

struct MainView: View {
    @EnvironmentObject var syncManager: CloudSyncManager
    @State private var showingDeleteAlert = false

    var textSize: CGFloat = Theme.textSize
    var horizontalPadding: CGFloat = Theme.horizontalPadding
    var verticalPadding: CGFloat = Theme.verticalPadding
    
    var body: some View {
        GradientTextWrapper(
            text: $syncManager.text,
            font: UIFont(name: Theme.font, size: textSize) ?? UIFont.systemFont(ofSize: textSize),
            padding: EdgeInsets(
                top: Theme.isIPadOrMac ? verticalPadding / 2 : 0,
                leading: Theme.isIPadOrMac ? verticalPadding / 2 : 0,
                bottom: verticalPadding,
                trailing: Theme.isIPadOrMac ? verticalPadding / 2 : 0,
            ),
            onShake: {
                showingDeleteAlert = true
            },
            topFadeHeight: Theme.isIPadOrMac ? textSize * 3 : 0,
            bottomFadeHeight: textSize * 3
        )
        .onChange(of: syncManager.text) { oldValue, newValue in
            syncManager.textDidChange(newValue)
        }
        .ignoresSafeArea(edges: .top)
        .alert("Discard all scraps?", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
            Button("Clear", role: .destructive) {
                syncManager.text = ""
                syncManager.textDidChange("")
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            }
        } message: {
            Text("It's good to forget things sometimes")
        }
    }
}
