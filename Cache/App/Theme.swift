//
//  Theme.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//

import SwiftUI

enum Theme {
    static let font = "RobotoMono-Regular"
    
    static let highlightColorLight = UIColor(
        hue: 24/360,
        saturation: 0.17,
        brightness: 1.0,
        alpha: 1.0
    )
    
    static let highlightColorDark = UIColor(
        hue: 23/360,
        saturation: 0.6,
        brightness: 0.35,
        alpha: 1.0
    )
    
    static let cursorColorLight = UIColor(
        hue: 23/360,
        saturation: 0.8,
        brightness: 1.0,
        alpha: 1.0
    )
    
    static let cursorColorDark = UIColor(
        hue: 23/360,
        saturation: 0.6,
        brightness: 1.0,
        alpha: 1.0
    )
    
    static let linkColor = UIColor.systemGray3
    
    static func dynamicHighlightColor(for traitCollection: UITraitCollection) -> UIColor {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return highlightColorDark
            default:
                return highlightColorLight
            }
        }
    }
    
    static func dynamicCursorColor(for traitCollection: UITraitCollection) -> UIColor {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return cursorColorDark
            default:
                return cursorColorLight
            }
        }
    }
}
