//
//  SeparatorView.swift
//  Cache
//
//  Created by Tim Lloyd on 2025-01-18.
//
//  Displays a visual separator between scraps with timestamp and dotted line

import SwiftUI

struct SeparatorView: View {
    let timestamp: Date

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: timestamp)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(formattedTimestamp)
                .font(.custom(Theme.font, size: Theme.separatorFontSize))
                .foregroundColor(Color(Theme.separatorColor))

            // Dotted line that fills remaining space
            DottedLine()
                .stroke(Color(Theme.separatorColor), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .frame(height: 1)
        }
    }
}

// Custom shape for dotted line
struct DottedLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
