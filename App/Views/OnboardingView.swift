import SwiftUI
import UIKit
import WritingCore

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                download.tag(1)
                enable.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < 2 { withAnimation { page += 1 } } else { model.settings.hasCompletedOnboarding = true }
            } label: {
                Text(page < 2 ? "Continue" : "Start writing").fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .accessibilityIdentifier("onboarding.continue")
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.bubble.fill").font(.system(size: 72)).foregroundStyle(Palette.accent)
            Text(Brand.name).font(.largeTitle.bold())
            Text("Fix your English in any app.\nFree. Private. On-device.")
                .font(.title3).multilineTextAlignment(.center).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Label("Fix grammar, spelling and punctuation", systemImage: "checkmark.circle")
                Label("Corrects sentences as you type", systemImage: "text.cursor")
                Label("Rewrite in any tone, translate, Ask AI", systemImage: "wand.and.stars")
                Label("No servers, no account, no ads", systemImage: "lock.shield")
            }
            .padding(.top, 8)
            Spacer()
        }
        .padding()
    }

    private var download: some View {
        let recommended = model.catalog.defaultModel
        return VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.circle.fill").font(.system(size: 60)).foregroundStyle(Palette.accent)
            Text("Download the AI model").font(.title2.bold())
            Text("\(recommended.name) runs on your iPhone. It's a one-time \(recommended.sizeDescription) download — use Wi-Fi.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            ModelRow(info: recommended, speed: nil, speedTest: {})
                .padding()
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
            Text("Smaller and larger models are available in the Models tab.").font(.footnote).foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
    }

    private var enable: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer()
            Text("Turn on the keyboard").font(.title2.bold())
            step(1, "Open Settings › General › Keyboard › Keyboards")
            step(2, "Tap Add New Keyboard… and choose \(Brand.name)")
            step(3, "Tap \(Brand.name) and turn on Allow Full Access")
            Text("Full Access lets the keyboard read the model downloaded by this app. \(Brand.name) has no servers: your text never leaves your iPhone, and the code is open source.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .padding()
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(.headline).frame(width: 28, height: 28)
                .background(Circle().fill(Palette.accent.opacity(0.15)))
            Text(text)
        }
    }
}
