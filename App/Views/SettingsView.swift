import SwiftUI
import WritingCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Picker("Keyboard layout", selection: $model.settings.keyboardLayout) {
                    ForEach(KeyboardLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.layout")
                Picker("Correct while typing", selection: $model.settings.autocorrectMode) {
                    ForEach(AutocorrectMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.autocorrect")
                Toggle("Review Fix before applying", isOn: $model.settings.showChangesBeforeApplying)
                Toggle("Spelling suggestions", isOn: $model.settings.spellingSuggestions)
                Toggle("Haptic feedback", isOn: $model.settings.hapticFeedback)
                Toggle("Key click sound", isOn: $model.settings.keyClickSound)
            } header: {
                Text("Keyboard")
            } footer: {
                Text("Automatic fixes clear French typos when you press Space on AZERTY. It also fixes small errors when you finish a sentence. You can undo either correction. Suggest shows sentence corrections above the keys for you to apply.")
            }

            Section("Privacy") {
                Label("Text is processed on your iPhone", systemImage: "iphone")
                Label("No account, ads, or analytics", systemImage: "hand.raised")
                Label("The keyboard makes no internet requests", systemImage: "wifi.slash")
                Text("Full Access lets the keyboard save status and diagnostics for this app. Your text stays on your iPhone.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Section("Help") {
                NavigationLink("Keyboard setup & help") { HelpView() }
                NavigationLink("Privacy policy") { PrivacyView() }
            }

            if let status = model.keyboardStatus {
                Section("Keyboard status") {
                    LabeledContent("Last seen", value: status.lastSeen.formatted(date: .abbreviated, time: .shortened))
                    if let name = status.modelName { LabeledContent("Model", value: name) }
                    if let peak = status.peakFootprintMB {
                        LabeledContent("Peak memory", value: String(format: "%.1f MB", peak))
                            .accessibilityIdentifier("settings.keyboardPeak")
                    }
                }
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
