//
//  GradientTextWrapper.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//

import SwiftUI
import SmoothGradient

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
                    let newValue = scrollView.contentOffset.y <= 0
                    if isScrolledToTop != newValue {
                        DispatchQueue.main.async {
                            isScrolledToTop = newValue
                        }
                    }
                }
            )
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            
            VStack(spacing: 0) {
                // Top gradient overlay
                SmoothLinearGradient(
                    from: Color(uiColor: .systemBackground).opacity(0.9),
                    to: Color(uiColor: .systemBackground).opacity(0),
                    startPoint: .top,
                    endPoint: .bottom,
                    curve: .easeOut
                )
                .frame(height: topFadeHeight)
                .opacity(Theme.isIPadOrMac ? 1 : (isScrolledToTop ? 0 : 1))
                .animation(.easeOut(duration: 0.2), value: isScrolledToTop)
                
                Spacer()
                
                // Bottom gradient overlay
                SmoothLinearGradient(
                    from: Color(uiColor: .systemBackground).opacity(0),
                    to: Color(uiColor: .systemBackground).opacity(0.9),
                    startPoint: .top,
                    endPoint: .bottom,
                    curve: .easeIn
                )
                .frame(height: bottomFadeHeight)
            }
            .allowsHitTesting(false)
        }
    }
}
