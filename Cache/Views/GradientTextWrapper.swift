//
//  GradientTextWrapper.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//

import SwiftUI

struct GradientTextWrapper: View {
    @Binding var text: String
    let font: UIFont
    let padding: EdgeInsets
    let onShake: () -> Void
    let topFadeHeight: CGFloat
    let bottomFadeHeight: CGFloat
    @FocusState private var isFocused: Bool
    @State private var isScrolledToTop = true
    
    var body: some View {
        ZStack {
            UITextViewWrapper(
                text: $text,
                font: font,
                padding: padding,
                onShake: onShake,
                onScroll: { scrollView in
                    isScrolledToTop = scrollView.contentOffset.y <= 0
                }
            )
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            
            VStack(spacing: 0) {
                // Top gradient that fades out when scrolled to top
                LinearGradient(
                    colors: [Color(.systemBackground), Color(.systemBackground).opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topFadeHeight)
                .opacity(isScrolledToTop ? 0 : 1)
                .animation(.easeOut(duration: 0.2), value: isScrolledToTop)
                
                Spacer()
                
                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: bottomFadeHeight)
            }
            .allowsHitTesting(false)
        }
    }
}
