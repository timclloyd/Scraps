//
//  TextLineManagerTests.swift
//  CacheTests
//
//  Created by Tim Lloyd on 2025-01-13.
//

import Testing
import Foundation
@testable import Cache

struct TextLineManagerTests {
    @Test
    func testAddLine() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test_notes.json")
        let manager = TextLineManager(saveURL: testFileURL)
        
        // Add test data
        manager.addLine("Test note")
        #expect(manager.lines.count == 1)
        #expect(manager.lines.first?.text == "Test note")
        
        manager.addLine("Another note")
        #expect(manager.lines.count == 2)
        #expect(manager.lines.last?.text == "Another note")
        
        // Cleanup
        try? FileManager.default.removeItem(at: testFileURL)
    }
    
    @Test
    func testPersistence() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let testFileURL = tempDir.appendingPathComponent("test_notes.json")
        
        // First manager
        let manager = TextLineManager(saveURL: testFileURL)
        manager.addLine("Test persistence")
        manager.addLine("Second line")
        
        // Create new manager with same URL to test loading
        let newManager = TextLineManager(saveURL: testFileURL)
        
        // Verify data
        #expect(newManager.lines.count == 2)
        #expect(newManager.lines.first?.text == "Test persistence")
        #expect(newManager.lines.last?.text == "Second line")
        
        // Cleanup
        try? FileManager.default.removeItem(at: testFileURL)
    }
}
