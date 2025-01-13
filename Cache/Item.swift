//
//  Item.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
