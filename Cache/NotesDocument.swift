//
//  NotesDocument.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-13.
//


// NotesDocument.swift
import SwiftUI

class NotesDocument: ObservableObject {
    @Published var lines: [TextLine] = []
    private let saveURL: URL
    
    init() {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        saveURL = documentsDirectory.appendingPathComponent("notes.json")
        loadData()
    }
    
    func addLine(_ text: String) {
        lines.append(TextLine(text: text))
        saveData()
    }
    
    private func loadData() {
        guard let data = try? Data(contentsOf: saveURL),
              let loadedLines = try? JSONDecoder().decode([TextLine].self, from: data) else {
            return
        }
        lines = loadedLines
    }
    
    private func saveData() {
        guard let data = try? JSONEncoder().encode(lines) else { return }
        try? data.write(to: saveURL)
    }
}
