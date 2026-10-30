import KeyboardUI
import SwiftUI
import WritingCore

/// The real keyboard UI, running inside the app against a simulated text field.
/// Lets people try it before enabling it in Settings, and lets UI tests drive it end to end.
struct KeyboardPreviewView: View {
    @EnvironmentObject var model: AppModel
    @StateObject private var document = ObservableTextDocument()
    @State private var controller: KeyboardController?
    // Held here because KeyboardController keeps its host weakly.
    @State private var host = PreviewKeyboardHost()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Try it: type a message with mistakes, finish a sentence, or tap Fix.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .bottom, spacing: 0) {
                        Text(document.text.isEmpty ? " " : document.text)
                            .accessibilityIdentifier("preview.text")
                            .accessibilityValue(document.text)
                        Rectangle().fill(Palette.accent).frame(width: 2, height: 20)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
                    Button("Clear") { document.clear(); controller?.textDidChange() }
                        .font(.footnote)
                        .accessibilityIdentifier("preview.clear")
                }
                .padding()
            }
            if let controller {
                KeyboardView(controller: controller)
                    .background(Color(.systemGray5))
            }
        }
        .onAppear {
            if controller == nil {
                let appModel = model
                controller = KeyboardController(document: document, host: host, settings: model.settings) {
                    try await appModel.assistant()
                }
            }
            controller?.settings = model.settings
        }
    }
}
