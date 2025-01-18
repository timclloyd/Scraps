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
    
    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        setupTextView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTextView()
    }
    
    private func setupTextView() {
        isSelectable = true
        isEditable = true
        
        // Configure custom link appearance
        linkTextAttributes = [
            .foregroundColor: UIColor { traitCollection in
                switch traitCollection.userInterfaceStyle {
                case .dark:
                    return .systemGray3
                default:
                    return .systemGray3
                }
            },
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
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
        self.inputView = nil
        return super.resignFirstResponder()
    }
}
