//
//  CustomTextView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-14.
//

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

        // Subtle link styling to match minimal aesthetic (gray + underline)
        linkTextAttributes = [
            .foregroundColor: Theme.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]

        // Custom cursor color to match accent color scheme
        tintColor = Theme.dynamicCursorColor(for: UITraitCollection.current)

        // Disable spell check to avoid red underlines (visual clutter)
        // but keep autocorrect suggestions for better typing experience
        spellCheckingType = .no
        autocorrectionType = .yes

    }
    
    // Detects device shake gesture to trigger clear action
    // Warning haptic provides physical feedback that gesture was registered
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

    // Ensures keyboard appears on first tap without requiring double-tap
    // Improves UX for quick text entry
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if !isFirstResponder {
            becomeFirstResponder()
        }
    }

    // Clear inputView before resigning to prevent custom input views
    // from persisting and interfering with keyboard restoration
    override func resignFirstResponder() -> Bool {
        self.inputView = nil
        return super.resignFirstResponder()
    }
}
