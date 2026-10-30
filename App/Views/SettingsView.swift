import SwiftUI
import UIKit
import WritingCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Keyboard setup") {
                    SetupRow(done: model.keyboardEnabled, title: "Add the \(Brand.name) keyboard",
                             detail: "Settings › General › Keyboard › Keyboards › Add New Keyboard")
                    SetupRow(done: model.keyboardStatus?.hasFullAccess == true, title: "Allow Full Access",
                             detail: "Lets the keyboard read the model this app downloaded. Nothing leaves your iPhone.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .accessibilityIdentifier("settings.openSettings")
                    if let status = model.keyboardStatus {
                        Text(Self.statusLine(status)).font(.caption).foregroundStyle(.secondary)
                    }
                }

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
                    Text("Writing")
                } footer: {
                    Text("Automatic fixes each sentence when you finish it (small changes only, one tap to undo). Suggest shows the fix above the keys instead.")
                }

                Section {
                    Toggle("Use GPU in the app", isOn: $model.settings.useGPU)
                } header: {
                    Text("Performance")
                } footer: {
                    Text("Applies after relaunching the app. The keyboard always runs on the CPU to stay within iOS keyboard memory limits.")
                }

                Section("Privacy") {
                    Label("Runs 100% on this iPhone", systemImage: "iphone")
                    Label("No account, no ads, no analytics", systemImage: "hand.raised")
                    Label("The keyboard never connects to the internet", systemImage: "wifi.slash")
                }

                Section("About") {
                    Link("Source code", destination: Brand.sourceURL)
                    Text("Free and open source (MIT). Inference by llama.cpp (MIT). Models by Liquid AI (LFM Open License v1.0).")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Show onboarding again") { model.settings.hasCompletedOnboarding = false }
                }
            }
            .navigationTitle("Settings")
            .onAppear { model.refresh() }
        }
    }
}

extension SettingsView {
    static func statusLine(_ status: KeyboardStatus) -> String {
        var line = "Keyboard last active " + status.lastSeen.formatted(.relative(presentation: .named))
        if let name = status.modelName { line += " · " + name }
        if let mb = status.footprintMB { line += String(format: " · %.0f MB", mb) }
        return line
    }
}

struct SetupRow: View {
    let done: Bool
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Palette.accent : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
