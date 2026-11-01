import SwiftUI
import UIKit
import WritingCore

struct GuidedSetupView: View {
    @EnvironmentObject var model: AppModel
    @State private var settingsError = false

    private var step: Int { model.settings.setupStep }

    var body: some View {
        Group {
            if step == 3 {
                KeyboardCheckView(isOnboarding: true)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        SetupProgress(step: step)
                        switch step {
                        case 1: download
                        case 2: enable
                        default: welcome
                        }
                    }
                    .padding(24)
                }
                .safeAreaInset(edge: .bottom) { actions }
                .navigationTitle("Lokey")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if step > 0 {
                    Button { model.settings.setupStep -= 1 } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .accessibilityIdentifier("onboarding.back")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Set up later") { model.isSettingUp = false }
                    .font(.subheadline)
                    .accessibilityIdentifier("onboarding.later")
            }
        }
        .alert("Could not open Settings", isPresented: $settingsError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Open the Settings app, then General → Keyboard → Keyboards → Add New Keyboard → Lokey.")
        }

    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            SetupHeading(symbol: "keyboard.fill", title: "Your words.\nA little clearer.",
                         detail: "An everyday keyboard with a little help from AI. All on your iPhone.")
            VStack(alignment: .leading, spacing: 24) {
                SetupFeature(symbol: "checkmark.bubble", title: "Fix the little things", detail: "Grammar, spelling, and punctuation as you type.")
                SetupFeature(symbol: "apps.iphone", title: "In the apps you already use", detail: "Choose Lokey where you normally type.")
                SetupFeature(symbol: "lock.shield", title: "Your text stays with you", detail: "No account, ads, or analytics. Works offline after download.")
            }
            .setupCard()
            VStack(alignment: .leading, spacing: 8) {
                Picker("Keyboard layout", selection: $model.settings.keyboardLayout) {
                    ForEach(KeyboardLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .accessibilityIdentifier("settings.layout")
                Text("English and French corrections. Review AI suggestions before you send.").font(.caption).foregroundStyle(.secondary)
            }
            .setupCard()
            NavigationLink("How Lokey protects your privacy") { PrivacyView() }
                .font(.footnote)
        }
    }

    private var download: some View {
        VStack(alignment: .leading, spacing: 24) {
            SetupHeading(symbol: "arrow.down.circle", title: "Download once.\nKeep it private.",
                         detail: "Download the AI model once. Your words are then processed on this iPhone.")
            VStack(alignment: .leading, spacing: 16) {
                if let active = model.activeModel {
                    Label("Ready for offline use", systemImage: "checkmark.circle.fill")
                        .font(.headline).foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("setup.modelReady")
                    Text(active.name).foregroundStyle(.secondary)
                } else {
                    ModelRow(info: model.catalog.defaultModel)
                }
            }
            .setupCard()
            Label("Use Wi-Fi and keep Lokey open until the download finishes.", systemImage: "wifi")
                .font(.footnote).foregroundStyle(.secondary)
            Text("You can also use Lokey for basic typing without a model.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var enable: some View {
        VStack(alignment: .leading, spacing: 24) {
            SetupHeading(symbol: "keyboard.badge.ellipsis", title: "Make room\nfor Lokey.",
                         detail: "iOS needs you to add the keyboard in Settings. It only takes a few taps.")
            VStack(alignment: .leading, spacing: 22) {
                SetupInstruction(number: 1, title: "Open Keyboards", detail: "In Settings, tap Apps → Lokey → Keyboards.")
                SetupInstruction(number: 2, title: "Turn on Lokey", detail: "Enable Lokey in the keyboard list.")
                SetupInstruction(number: 3, title: "Allow Full Access · optional", detail: "This lets the keyboard save setup status and diagnostics to this app. Lokey never sends your text to a server.")
            }
            .setupCard()
            DisclosureGroup("Don’t see Keyboards?") {
                Text("Go to the main Settings list → General → Keyboard → Keyboards → Add New Keyboard → Lokey.")
                    .padding(.top, 8)
            }
            .font(.subheadline)
            DisclosureGroup("Why does Apple show a warning?") {
                Text("Full Access gives keyboards permission to connect to the internet. Lokey’s keyboard makes no internet requests. Basic typing works without this permission. Without it, this app cannot confirm the keyboard’s status.")
                    .padding(.top, 8)
            }
            .font(.subheadline)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            switch step {
            case 1:
                if model.activeModel != nil {
                    Button("Continue") { model.settings.setupStep = 2 }
                        .setupPrimary("onboarding.continue")
                } else {
                    Button("Download later") { model.settings.setupStep = 2 }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("onboarding.downloadLater")
                }
            case 2:
                Button("Open iPhone Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url) { success in settingsError = !success }
                }
                .setupPrimary("setup.openSettings")
                Button("I’ve added Lokey") { model.settings.setupStep = 3 }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("onboarding.check")
            default:
                Button("Set up my keyboard") { model.settings.setupStep = 1 }
                    .setupPrimary("onboarding.start")
                Text("Free. No account needed.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}

struct SetupProgress: View {
    let step: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STEP \(step + 1) OF 4").font(.caption.weight(.semibold)).tracking(1.5)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(0..<4) { index in
                    Capsule().fill(index <= step ? Palette.accent : Color.secondary.opacity(0.15))
                        .frame(height: 4)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

struct SetupHeading: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Palette.accent)
                .frame(width: 72, height: 72)
                .background(Palette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
            Text(title).font(.largeTitle.bold()).tracking(-0.8).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SetupFeature: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Palette.accent).frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct SetupInstruction: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.subheadline.bold()).foregroundStyle(Palette.accent)
                .frame(width: 28, height: 28)
                .background(Palette.accent.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    func setupCard() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
    }

    func setupPrimary(_ id: String) -> some View {
        self.buttonStyle(SetupPrimaryStyle())
            .accessibilityIdentifier(id)
    }
}


private struct SetupPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .foregroundStyle(.white)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 16))
    }
}
