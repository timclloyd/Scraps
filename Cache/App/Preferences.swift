//
//  Preferences.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//
//  App preferences and configuration values

import Foundation
import CoreGraphics

enum Preferences {
    /// Corner radius applied to the top corners of the latest scrap panel.
    static let latestPanelCornerRadius: CGFloat = 16

    /// Toolbar height matches the device's top safe area inset (notch / Dynamic Island height)
    /// and is read dynamically from GeometryProxy.safeAreaInsets.top at runtime.
}
