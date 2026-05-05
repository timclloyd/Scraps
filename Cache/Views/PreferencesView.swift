import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var documentManager: DocumentManager
    @FocusState private var focusedField: HighlightField?
    let searchButtonCenterTrailingInset: CGFloat
    let keyboardHeight: CGFloat
    let onDismiss: () -> Void

    private enum HighlightField: Hashable {
        case green
        case blue
        case red
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            form
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var form: some View {
        ScrollViewReader { proxy in
            Form {
                highlightSection(
                    field: .green,
                    color: .green,
                    text: binding(for: \.green)
                )

                highlightSection(
                    field: .blue,
                    color: .blue,
                    text: binding(for: \.blue)
                )

                highlightSection(
                    field: .red,
                    color: .red,
                    text: binding(for: \.red)
                )
            }
            .scrollDismissesKeyboard(.never)
            .contentMargins(.bottom, keyboardHeight + Theme.cursorScrollPadding, for: .scrollContent)
            .animation(.easeOut(duration: 0.25), value: keyboardHeight)
            .onChange(of: keyboardHeight) { _, _ in
                scrollFocusedField(with: proxy)
            }
            .onChange(of: focusedField) { _, _ in
                scrollFocusedField(with: proxy)
            }
        }
    }

    private var header: some View {
        GeometryReader { geometry in
            let titleWidth = min(geometry.size.width / 2, 220)

            ZStack {
                Text("Highlights")
                    .font(.headline)
                    .frame(width: titleWidth)

                Button {
                    focusedField = nil
                    dismissKeyboard()
                    documentManager.flushHighlightSettingsSave()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundColor(Color(uiColor: .label))
                            .frame(width: 44, height: 44)
                            .padding(.trailing, max(searchButtonCenterTrailingInset - 22, 0))
                    }
                    .frame(
                        width: max((geometry.size.width - titleWidth) / 2, 44),
                        height: 44
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .frame(height: 44)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func highlightSection(field: HighlightField, color: Color, text: Binding<String>) -> some View {
        Section {
            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(minHeight: 96)
                .focused($focusedField, equals: field)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color.opacity(0.28))
                .frame(width: 52, height: Theme.textSize)
        }
        .id(field)
    }

    private func scrollFocusedField(with proxy: ScrollViewProxy) {
        guard let focusedField, keyboardHeight > 0 else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(focusedField, anchor: .bottom)
            }
        }
    }

    private func binding(for keyPath: WritableKeyPath<HighlightSettings, String>) -> Binding<String> {
        Binding(
            get: {
                documentManager.highlightSettings[keyPath: keyPath]
            },
            set: { value in
                var settings = documentManager.highlightSettings
                settings[keyPath: keyPath] = value
                documentManager.updateHighlightSettings(settings)
            }
        )
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
