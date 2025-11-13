//
//  Preferences.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//
//  App preferences and configuration values

import Foundation

enum Preferences {
    /// Time threshold (in seconds) for creating a new scrap after app closure
    /// If elapsed time since last close exceeds this value, a new scrap is created
    static let newScrapThresholdSeconds: TimeInterval = (60 * 5)

    /// Vertical padding (in points) to maintain above and below the cursor when scrolling
    /// Ensures cursor stays comfortably visible away from screen edges and keyboard
    static let cursorScrollPadding: CGFloat = Theme.textSize * 2
}
