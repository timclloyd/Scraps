import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var documentManager: DocumentManager
    let searchButtonCenterTrailingInset: CGFloat
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header

            Form {
                highlightSection(
                    color: .green,
                    text: binding(for: \.green)
                )

                highlightSection(
                    color: .blue,
                    text: binding(for: \.blue)
                )

                highlightSection(
                    color: .red,
                    text: binding(for: \.red)
                )
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var header: some View {
        ZStack {
            Text("Highlights")
                .font(.headline)

            HStack {
                Spacer()

                Button {
                    dismissKeyboard()
                    documentManager.flushHighlightSettingsSave()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDismiss()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(Color(uiColor: .label))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Done")
                .padding(.trailing, max(searchButtonCenterTrailingInset - 22, 0))
            }
        }
        .frame(height: 44)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func highlightSection(color: Color, text: Binding<String>) -> some View {
        Section {
            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(minHeight: 96)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        } header: {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(color.opacity(0.28))
                .frame(width: 52, height: Theme.textSize)
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
