import SwiftUI
import UIKit
import WritingCore

struct KeyboardSetupView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Palette.accent)
                    Text("Set up your keyboard")
                        .font(.title.bold())
                    Text("Download once. Then type and fix text in your usual apps.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                step(1, title: model.activeModel == nil ? "Download the model" : "Model ready") {
                    if let active = model.activeModel {
                        Label(active.name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.accent)
                            .accessibilityIdentifier("setup.modelReady")
                        Text("Downloaded. Corrections run on your iPhone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Download once over Wi-Fi. After that, the keyboard works offline.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ModelRow(info: model.catalog.defaultModel)
                    }
                    NavigationLink("Manage models") { ModelsView() }
                        .accessibilityIdentifier("setup.models")
                }

                step(2, title: "Enable the keyboard") {
                    Text("In iPhone Settings, go to the main list, then General → Keyboard → Keyboards → Add New Keyboard. Choose Lokey.")
                        .font(.subheadline)
                    Text("Tap Lokey and turn on Allow Full Access to share settings with this app. Your text still stays on your iPhone.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Open iPhone Settings", action: openSettings)
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("setup.openSettings")
                }

                step(3, title: "Use Lokey in your apps") {
                    Label("Hold the globe key and choose Lokey.", systemImage: "globe")
                        .font(.subheadline)
                    Text("To put Lokey first in the list: in iPhone Settings → General → Keyboard → Keyboards, tap Edit and drag Lokey to the top.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink { KeyboardCheckView() } label: {
                        Label("Check your keyboard", systemImage: "keyboard")
                    }
                    .accessibilityIdentifier("setup.checkKeyboard")
                    if let status = model.keyboardStatus {
                        Text("Keyboard last used " + status.lastSeen.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Label("No account. No ads. Your text stays on your iPhone.", systemImage: "lock.shield")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("iOS uses its own keyboard for passwords and some other fields. Some apps can also block custom keyboards.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle(Brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("setup.screen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView() } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("setup.settings")
            }
        }
        .onAppear { model.refresh() }
    }

    private func step<Content: View>(_ number: Int, title: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("\(number)").font(.subheadline.bold())
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.accent.opacity(0.12)))
                    .foregroundStyle(Palette.accent)
                Text(title).font(.headline)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct KeyboardCheckView: View {
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This uses your iPhone's selected keyboard. Hold the globe key and choose Lokey.")
                .foregroundStyle(.secondary)
            Text("Try typing “I has 2 kid”, then tap Fix above the keys and Apply.")
                .font(.subheadline)
            TextEditor(text: $text)
                .autocorrectionDisabled()
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                .accessibilityLabel("Try your keyboard")
                .accessibilityIdentifier("setup.testText")
            Text("You can now use the same keyboard in Messages, Notes, and your other apps.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Check your keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { text = "" }
                    .accessibilityIdentifier("setup.clearTest")
            }
        }
    }
}
