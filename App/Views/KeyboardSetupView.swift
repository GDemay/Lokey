import AppleRuntime
import SwiftUI
import WritingCore

struct KeyboardSetupView: View {
    @EnvironmentObject var model: AppModel

    private var wasChecked: Bool {
        guard let status = model.keyboardStatus else { return false }
        if model.settings.useAppleIntelligenceForFix {
            return status.hasFullAccess && status.appleFixReady == true && AppleFix.unavailableReason == nil
        }
        return status.modelID != nil && status.modelID == model.activeModel?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SetupHeading(symbol: "keyboard.fill", title: "A little help.\nIn every word.",
                             detail: "Your everyday keyboard, with private AI on your iPhone.")
                VStack(alignment: .leading, spacing: 16) {
                    Label(wasChecked ? "Keyboard checked" : "Let’s get you typing", systemImage: wasChecked ? "checkmark.circle.fill" : "keyboard")
                        .font(.headline).foregroundStyle(Palette.accent)
                    if let status = model.keyboardStatus, wasChecked {
                        Text("Last checked " + status.lastSeen.formatted(.relative(presentation: .named)))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Text("Add Lokey in Settings, then choose it with the globe key.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Button(wasChecked ? "Show setup guide" : "Continue keyboard setup") { model.startSetup() }
                        .setupPrimary("setup.resume")
                    NavigationLink { KeyboardCheckView() } label: {
                        Label("Check your keyboard", systemImage: "keyboard")
                    }
                    .accessibilityIdentifier("setup.checkKeyboard")
                }
                .setupCard()

                VStack(spacing: 0) {
                    NavigationLink { ModelsView() } label: {
                        homeRow(symbol: "cpu", title: "AI model",
                                detail: model.settings.useAppleIntelligenceForFix ? "Apple Intelligence for Fix"
                                    : model.activeModel?.name ?? "Download for offline corrections")
                    }
                    .accessibilityIdentifier("setup.models")
                    Divider().padding(.vertical, 16)
                    NavigationLink { CorrectionHistoryView() } label: {
                        homeRow(symbol: "book", title: "Correction history", detail: "Learn from your corrections")
                    }
                    .accessibilityIdentifier("setup.learn")
                    Divider().padding(.vertical, 16)
                    NavigationLink { SettingsView() } label: {
                        homeRow(symbol: "slider.horizontal.3", title: "Make it yours", detail: "Corrections, sound, and feel")
                    }
                    .accessibilityIdentifier("setup.settings")
                    Divider().padding(.vertical, 16)
                    NavigationLink { HelpView() } label: {
                        homeRow(symbol: "questionmark.circle", title: "Help & privacy", detail: "Quick answers, without the jargon")
                    }
                }
                .buttonStyle(.plain)
                .setupCard()
                if model.activeModel != nil || model.settings.useAppleIntelligenceForFix && AppleFix.unavailableReason == nil {
                    Label("Model ready · works offline", systemImage: "checkmark.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("setup.modelReady")
                }
                Text("Free. No account. No ads.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Lokey")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("setup.screen")
        .onAppear { model.refresh() }
    }

    private func homeRow(symbol: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}

struct KeyboardCheckView: View {
    @EnvironmentObject var model: AppModel
    var isOnboarding = false
    @State private var text = ""
    @State private var checkID = ""
    @FocusState private var focused: Bool

    private var verified: Bool {
        if model.settings.useAppleIntelligenceForFix {
            guard let status = model.keyboardStatus else { return false }
            return status.checkID == checkID && status.hasFullAccess && status.appleFixReady == true
                && AppleFix.unavailableReason == nil
        }
        return model.keyboardStatus?.verifies(checkID: checkID, modelID: model.activeModel?.id) == true
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isOnboarding { SetupProgress(step: 3) }
                Text(verified ? "You’re ready to type." : "Meet your new keyboard.")
                    .font(.title.bold())
                Label("Hold the globe key. Choose Lokey.", systemImage: "globe")
                    .font(.headline)
                Text("Try “I has 2 kid”, then tap Fix and Apply. You should see “I have 2 kids.”")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextEditor(text: $text)
                    .focused($focused)
                    .autocorrectionDisabled()
                    .padding(8).frame(height: 112)
                    .scrollContentBackground(.hidden)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Try your keyboard")
                    .accessibilityIdentifier("setup.testText")
                if verified {
                    Label("Lokey is connected. Your AI model is ready.", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("setup.verified")
                } else {
                    Text("No confirmation yet? Choose Lokey and tap a key. Allow Full Access in Settings if you want this app to check its status. You can still type without it.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.activeModel == nil && !model.settings.useAppleIntelligenceForFix {
                        Text("Download an AI model from the home screen to use Fix.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if isOnboarding {
                    Button(verified ? "Start using Lokey" : "Finish without checking") {
                        focused = false
                        model.finishSetup()
                    }
                    .setupPrimary("onboarding.finish")
                }
                DisclosureGroup("Make Lokey your main keyboard") {
                    Text("In Settings → General → Keyboard → Keyboards, tap Edit. Drag Lokey to the top. iOS still uses its own keyboard for passwords and some other fields.")
                        .font(.footnote).padding(.top, 8)
                }
                .font(.subheadline)
            }
            .padding(24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Check your keyboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Clear") { text = "" }.accessibilityIdentifier("setup.clearTest")
                Button { focused.toggle() } label: { Image(systemName: focused ? "keyboard.chevron.compact.down" : "keyboard") }
                    .accessibilityLabel(focused ? "Hide keyboard" : "Show keyboard")
            }
        }
        .task {
            checkID = model.beginKeyboardCheck()
            focused = true
            while !Task.isCancelled {
                model.refreshKeyboardStatus()
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
    }
}
