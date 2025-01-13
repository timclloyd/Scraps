//
//  TextLine.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import Foundation

struct TextLine: Identifiable, Codable {
    let id: UUID
    var text: String
    let creationDate: Date
    
    init(text: String, creationDate: Date = Date()) {
        self.id = UUID()
        self.text = text
        self.creationDate = creationDate
    }
}
