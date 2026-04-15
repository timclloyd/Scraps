//
//  ToolbarView.swift
//  Cache
//

import SwiftUI

struct ToolbarView: View {
    let viewMode: ViewMode
    let topHeight: CGFloat
    let onToggleMode: () -> Void
    let onToggleSearch: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleMode) {
                Image(systemName: viewMode == .latest ? "archivebox" : "calendar")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color(uiColor: .label))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -6) // adjust optical horizontal alignment

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onToggleSearch) {
                Image(systemName: viewMode == .search ? "checkmark" : "magnifyingglass")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color(uiColor: .label))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: topHeight)
        .background(Theme.archiveBackground)
    }
}
