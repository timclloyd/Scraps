//
//  ToolbarView.swift
//  Cache
//

import SwiftUI

struct ToolbarView: View {
    let viewMode: ViewMode
    let topHeight: CGFloat
    let controlTopPadding: CGFloat
    var hidesButtons = false
    let onToggleMode: () -> Void
    let onToggleSearch: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onToggleMode) {
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    Image(systemName: modeToggleIconName(for: timeline.date))
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color(uiColor: .label))
                        .contentTransition(.symbolEffect(.replace))
                        .animation(.easeInOut(duration: 0.2), value: viewMode)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, -6) // adjust optical horizontal alignment
            .opacity(hidesButtons ? 0 : 1)
            .allowsHitTesting(!hidesButtons)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button(action: onToggleSearch) {
                Image(systemName: viewMode == .search ? "checkmark" : "magnifyingglass")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(Color(uiColor: .label))
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.easeInOut(duration: 0.2), value: viewMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hidesButtons ? 0 : 1)
            .allowsHitTesting(!hidesButtons)
        }
        .padding(.top, controlTopPadding)
        .frame(height: topHeight, alignment: .top)
        .background(Theme.archiveBackground)
    }

    private func modeToggleIconName(for date: Date) -> String {
        guard viewMode != .latest else { return "clock" }

        if #available(iOS 26.0, *) {
            let day = Calendar.current.component(.day, from: date)
            return "\(day).calendar"
        }

        return "calendar"
    }
}
