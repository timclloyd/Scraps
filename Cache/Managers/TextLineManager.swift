//
//  TextLineManager.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//

import SwiftUI

class TextLineManager: ObservableObject {
    @Published var lines: [TextLineModel] = []
    private let saveURL: URL
    
    init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = documentsDirectory.appendingPathComponent("notes.json")
        loadData()
    }
    
    func addLine(_ text: String) {
        lines.append(TextLineModel(text: text))
        saveData()
    }
    
    private func loadData() {
        guard let data = try? Data(contentsOf: saveURL),
              let loadedLines = try? JSONDecoder().decode([TextLineModel].self, from: data) else {
            return
        }
        lines = loadedLines
    }
    
    private func saveData() {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        try? data.write(to: saveURL)
    }
}
