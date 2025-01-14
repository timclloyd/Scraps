//
//  CustomTextView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//
//  Custom UITextView with shake detection

import SwiftUI

class CustomTextView: UITextView {
    var onShake: (() -> Void)?
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            // Generate haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
            onShake?()
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return true
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }
    
    override func resignFirstResponder() -> Bool {
        // Allow normal resignation of first responder status
        self.inputView = nil
        return super.resignFirstResponder()
    }
}
