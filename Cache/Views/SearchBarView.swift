//
//  SearchBarView.swift
//  Cache
//

import SwiftUI

struct SearchBarView: View {
    @Binding var query: String
    let matchCount: Int
    let currentMatchIndex: Int
    let onPrev: () -> Void
    let onNext: () -> Void
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool

    private var counterText: String {
        if query.isEmpty { return "" }
        if matchCount == 0 { return "No matches" }
        return "\(currentMatchIndex + 1) of \(matchCount)"
    }

    var body: some View {
        HStack() {
            Image(systemName: "magnifyingglass")
                .font(.system(size: Theme.textSize))
                .foregroundColor(.secondary)

            TextField("Search...", text: $query)
                .font(.custom(Theme.font, size: Theme.textSize))
                .focused($isFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .onSubmit(onDismiss)

            if !query.isEmpty {
                Text(counterText)
                    .font(.custom(Theme.font, size: Theme.separatorFontSize))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .fixedSize()

                HStack(spacing: 0) {
                    Button(action: onPrev) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: Theme.textSize, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(matchCount <= 1)
                    .buttonStyle(.plain)

                    Button(action: onNext) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: Theme.textSize, weight: .medium))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(matchCount <= 1)
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 44)
        .padding(.horizontal, Theme.horizontalPadding)
        .background(Theme.archiveBackground)
        .onAppear {
            isFocused = true
        }
    }
}
