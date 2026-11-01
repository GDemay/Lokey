import SwiftUI
import WritingCore

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                SetupFeature(symbol: "lock.shield", title: "Your words stay on your iPhone", detail: "Lokey processes text on your device. We do not collect your text or send it to a server.")
                    .padding(.vertical, 8)
            }
            Section("What stays on your phone") {
                Text("The keyboard reads nearby text to suggest and apply edits. Your settings, downloaded models, and basic keyboard status stay in shared storage on this iPhone.")
                Text("System diagnostics can include model names, timings, and memory use. Lokey does not log what you type.")
            }
            Section("What uses the internet") {
                Text("Only the main app downloads AI models from Hugging Face. Those downloads expose normal connection details, such as your IP address, to the download provider. Your typed text is not part of the request.")
                Text("The keyboard makes no internet requests. Lokey has no accounts, advertising, analytics, or tracking.")
            }
            Section("Full Access is your choice") {
                Text("Apple shows the same broad warning for all keyboards that request Full Access. In Lokey, it lets the keyboard save status and diagnostics for this app. Basic typing remains available without it.")
            }
            Section("You stay in control") {
                Text("Remove model files in Models. Turn off automatic correction in Settings. Remove Lokey in iPhone Settings → General → Keyboard → Keyboards. Deleting Lokey removes its local app data.")
                Link("Read the source code", destination: Brand.sourceURL)
                Link("Ask a privacy question", destination: URL(string: "https://github.com/GDemay/Lokey/issues/new")!)
            }
        }
        .navigationTitle("Privacy")
    }
}

struct HelpView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        List {
            Section("Keyboard setup") {
                Button("Show the setup guide") { model.startSetup() }
                NavigationLink("Check the real keyboard") { KeyboardCheckView() }
            }
            Section {
                answer("Lokey is missing from the globe menu", "Add Lokey in Settings → General → Keyboard → Keyboards → Add New Keyboard. Then hold the globe key in a text field and choose Lokey.")
                answer("The Apple keyboard appears instead", "iOS uses its own keyboard for passwords, phone numbers, and some other fields. Apps can also block custom keyboards. Try a normal text field in Notes.")
                answer("Fix is not working", "Open Models and check that a model is downloaded. Switch to another keyboard and back to reload Lokey. Try a short English or French sentence. AI can miss errors; check suggestions before you send.")
                answer("What does Automatic do?", "It fixes small errors when you finish a sentence. Tap Undo above the keys to restore your text. Choose Suggest in Settings to approve each correction instead.")
                answer("How do I make Lokey my main keyboard?", "In Settings → General → Keyboard → Keyboards, tap Edit. Drag Lokey to the top. You can switch keyboards at any time with the globe key.")
            } header: { Text("Quick answers") }
            Section("Privacy & support") {
                NavigationLink("Privacy policy") { PrivacyView() }
                Link("Report a problem", destination: URL(string: "https://github.com/GDemay/Lokey/issues/new")!)
                Text("Please include your iPhone model, iOS version, and what happened. Do not include private text.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Help & privacy")
    }

    private func answer(_ title: String, _ detail: String) -> some View {
        DisclosureGroup(title) { Text(detail).font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8) }
    }
}
