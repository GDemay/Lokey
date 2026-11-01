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
    var body: some View {
        NavigationStack {
            KeyboardSetupView()
        }
    }
}
