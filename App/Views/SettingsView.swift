import SwiftUI
import WritingCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Correct while typing", selection: $model.settings.autocorrectMode) {
                    ForEach(AutocorrectMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.autocorrect")
                Toggle("Show changes before applying Fix", isOn: $model.settings.showChangesBeforeApplying)
                Toggle("Spelling suggestions", isOn: $model.settings.spellingSuggestions)
                Toggle("Haptic feedback", isOn: $model.settings.hapticFeedback)
                Toggle("Key click sound", isOn: $model.settings.keyClickSound)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Automatic fixes small errors when you finish a sentence, with one tap to undo. Suggest shows a correction above the keys for you to apply.")
            }

            Section("Privacy") {
                Label("Text is processed on your iPhone", systemImage: "iphone")
                Label("No account, ads, or analytics", systemImage: "hand.raised")
                Label("The keyboard makes no internet requests", systemImage: "wifi.slash")
                Text("Full Access lets Lokey share settings with its keyboard. It does not send your text anywhere.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("About") {
                Link("Source code", destination: Brand.sourceURL)
                Text("Free and open source (MIT). AI models by Liquid AI, under the LFM Open License v1.0.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
