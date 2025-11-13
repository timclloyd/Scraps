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
}
