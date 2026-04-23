//
//  Theme.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//

import SwiftUI

enum Theme {
    
    //MARK: Animation
    
    static let navigationIn = Animation.spring(
        response: 0.3,
        dampingFraction: 1.0
    )

    static let navigationOut = Animation.easeIn(
        duration: 0.3
    )

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
            return UIColor.systemYellow.withAlphaComponent(0.2)
        default:
            return UIColor.systemYellow.withAlphaComponent(0.2)
        }
    }

    static let searchActiveHighlightColor = UIColor { traitCollection in
        switch traitCollection.userInterfaceStyle {
        case .dark:
            return UIColor.systemYellow.withAlphaComponent(0.5)
        default:
            return UIColor.systemYellow.withAlphaComponent(0.5)
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
    
    //MARK: Valence minimap

    /// Visible width of the coloured strip. Drives the archive's trailing
    /// content inset so text isn't squeezed by the tap-extension below.
    static var minimapWidth: CGFloat { isIPhone ? 12 : 12 }

    /// Total width of the minimap's tap target. Exceeds `minimapWidth` so the
    /// strip is easy to hit with a fingertip without stealing text real estate.
    /// The extra width overlaps the scrap's right-side padding, not its glyphs.
    static var minimapTapWidth: CGFloat { isIPhone ? 20 : 28 }

    static func minimapColor(for band: ValenceBand) -> Color {
        let base: UIColor
        switch band {
        case .positive: base = .systemGreen
        case .negative: base = .systemRed
        case .neutral:  base = .systemBlue
        }
        return Color(base)
    }

    /// Effective segment opacity for the minimap strip. Keeps all minimap alpha
    /// tuning in one place: light mode ranges from 0.2 to 0.4; dark mode ranges
    /// from 0.3 to 0.6.
    static func minimapOpacity(forHitCount count: Int, colorScheme: ColorScheme) -> CGFloat {
        let range: (min: CGFloat, max: CGFloat) = colorScheme == .dark ? (0.3, 0.6) : (0.2, 0.4)
        let countCap: CGFloat = 4
        let t = min(CGFloat(max(count, 1) - 1) / (countCap - 1), 1.0)
        return range.min + t * (range.max - range.min)
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
