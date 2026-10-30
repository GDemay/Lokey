import SwiftUI
import WritingCore

@main
struct LokeyApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Palette.accent)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refresh() }
                }
        }
    }
}

enum Palette {
    static let accent = Color(red: 0.13, green: 0.55, blue: 0.42)
    static let inserted = Color(red: 0.10, green: 0.62, blue: 0.35)
    static let removed = Color(red: 0.86, green: 0.24, blue: 0.24)
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = Tab.write

    enum Tab: Hashable { case write, keyboard, models, settings }

    var body: some View {
        TabView(selection: $tab) {
            EditorView(openModels: { tab = .models })
                .tabItem { Label("Write", systemImage: "square.and.pencil") }
                .tag(Tab.write)
            KeyboardPreviewView()
                .tabItem { Label("Keyboard", systemImage: "keyboard") }
                .tag(Tab.keyboard)
            ModelsView()
                .tabItem { Label("Models", systemImage: "cpu") }
                .tag(Tab.models)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .fullScreenCover(isPresented: Binding(
            get: { !model.settings.hasCompletedOnboarding },
            set: { if !$0 { model.settings.hasCompletedOnboarding = true } }
        )) {
            OnboardingView()
        }
    }
}
