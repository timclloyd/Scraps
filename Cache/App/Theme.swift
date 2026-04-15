//
//  Theme.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//

import SwiftUI

enum Theme {
    
    //MARK: Animation

    static let navigationAnimation = Animation.spring(response: 0.2, dampingFraction: 1.0)

    //MARK: Fonts
    
    static let textSize: CGFloat = 16
    static let font = "RobotoMono-Regular"

    //MARK: Layout
    
    static let horizontalPadding: CGFloat = 16
    static let horizontalPaddingBackground: CGFloat = 4
    static let verticalPadding: CGFloat = 48

    static let separatorFontSize: CGFloat = 12
    static let separatorVerticalPadding: CGFloat = 24

    static let topFadeHeight: CGFloat = 48
    static let bottomFadeHeight: CGFloat = 48
    
    /// Vertical padding to maintain above and below the cursor when scrolling
    /// Ensures cursor stays comfortably visible away from screen edges and keyboard
    static let cursorScrollPadding: CGFloat = textSize * 2
    
    //MARK: Colours

    static let archiveBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemBackground : .systemGray6
    })

    static let latestPanelBackground = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark ? .systemGray6 : .systemBackground
    })
    static let strikethroughHapticStyle = UIImpactFeedbackGenerator.FeedbackStyle.medium

    static let linkColor = UIColor.systemGray3
    static let panelBorderColor = UIColor.systemGray5
    static let separatorColor = UIColor.systemGray3
    
    static func highlightColor(for traitCollection: UITraitCollection) -> UIColor {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(
                    hue: 23/360,
                    saturation: 0.6,
                    brightness: 0.35,
                    alpha: 1.0
                )
            default:
                return UIColor(
                    hue: 24/360,
                    saturation: 0.17,
                    brightness: 1.0,
                    alpha: 1.0
                )
            }
        }
    }
    
    static let searchHighlightColor = UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hue: 23/360, saturation: 0.55, brightness: 0.50, alpha: 1.0)
        default:
            return UIColor(hue: 24/360, saturation: 0.30, brightness: 1.0, alpha: 1.0)
        }
    }

    static let searchActiveHighlightColor = UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor(hue: 23/360, saturation: 0.70, brightness: 0.72, alpha: 1.0)
        default:
            return UIColor(hue: 24/360, saturation: 0.58, brightness: 1.0, alpha: 1.0)
        }
    }

    static func cursorColor(for traitCollection: UITraitCollection) -> UIColor {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(
                    hue: 23/360,
                    saturation: 0.6,
                    brightness: 1.0,
                    alpha: 1.0
                )
            default:
                return UIColor(
                    hue: 23/360,
                    saturation: 0.8,
                    brightness: 1.0,
                    alpha: 1.0
                )
            }
        }
    }

    // Background of focused scrap
    static func focusBackgroundColor(for traitCollection: UITraitCollection) -> UIColor {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor.systemGray6.withAlphaComponent(0.67)
            default:
                return UIColor.systemGray6.withAlphaComponent(0.67)
            }
        }
    }
    
    //MARK: Platform detection
    static var isIPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    static var isIPadOrMac: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #elseif targetEnvironment(macCatalyst)
        return true
        #elseif os(macOS)
        return true
        #else
        return false
        #endif
    }
}
