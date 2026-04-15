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
        HStack {
            modeToggleButton
            Spacer()
            searchButton
        }
        .frame(height: topHeight)
        .padding(.horizontal, Theme.horizontalPadding)
        .background(Theme.archiveBackground)
    }

    private var modeToggleButton: some View {
        Button(action: onToggleMode) {
            HStack(spacing: 4) {
                Text(viewMode == .latest ? "SCRAPS" : "TODAY")
                Image(systemName: viewMode == .latest ? "archivebox" : "calendar")
            }
            .font(.custom(Theme.font, size: Theme.separatorFontSize))
            .fontWeight(.medium)
            .foregroundColor(Color(uiColor: .label))
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    private var searchButton: some View {
        Button(action: onToggleSearch) {
            HStack(spacing: 4) {
                Image(systemName: viewMode == .search ? "checkmark" : "magnifyingglass")
                Text(viewMode == .search ? "DONE" : "SEARCH")
            }
            .font(.custom(Theme.font, size: Theme.separatorFontSize))
            .fontWeight(.medium)
            .foregroundColor(Color(uiColor: .label))
            .padding(10)
        }
        .buttonStyle(.plain)
    }
}
