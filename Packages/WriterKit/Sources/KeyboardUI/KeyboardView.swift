#if canImport(UIKit)
import SwiftUI
import UIKit
import WritingCore

/// Apple-keyboard-like palette that follows light/dark mode.
enum KeyboardStyle {
    static let keyHeight: CGFloat = 43
    static let rowSpacing: CGFloat = 11
    static let keySpacing: CGFloat = 6
    static let toolbarHeight: CGFloat = 46
    static var keysHeight: CGFloat { keyHeight * 4 + rowSpacing * 3 + 12 }
    static let bottomInset: CGFloat = 2
    // Portrait metrics from the French–English keyboard on iPhone 17 Pro.
    static let azertyTopInset: CGFloat = 4
    static let azertyToolbarHeight: CGFloat = 48
    static let azertyKeysHeight: CGFloat = 212

    static let letterKey = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white })
    static let azertyKey = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 60.0 / 255, alpha: 1) : .white })
    static let specialKey = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) })
    static let pressedKey = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.55, alpha: 1) : UIColor(red: 0.84, green: 0.85, blue: 0.87, alpha: 1) })
    static let shadow = Color.black.opacity(0.3)
    static let accent = Color(red: 0.13, green: 0.55, blue: 0.42)
    static let inserted = Color(red: 0.10, green: 0.62, blue: 0.35)
    static let previewBackground = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.17, alpha: 1) : .white })
    static let previewAdded = Color(UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(red: 0.54, green: 0.90, blue: 0.68, alpha: 1)
            : UIColor(red: 0.00, green: 0.40, blue: 0.24, alpha: 1)
    })
    static let previewRemoved = Color(UIColor {
        $0.userInterfaceStyle == .dark ? UIColor(red: 1.00, green: 0.66, blue: 0.66, alpha: 1)
            : UIColor(red: 0.68, green: 0.14, blue: 0.17, alpha: 1)
    })
}

public struct KeyboardView: View {
    @ObservedObject var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    /// Height the host should give the keyboard (toolbar + keys + bottom inset).
    public static func preferredHeight(for layout: KeyboardLayout) -> CGFloat {
        if layout.resolved() == .azerty {
            return KeyboardStyle.azertyToolbarHeight + KeyboardStyle.azertyKeysHeight
        }
        return KeyboardStyle.toolbarHeight + KeyboardStyle.keysHeight + KeyboardStyle.bottomInset
    }

    public var body: some View {
        let isAzerty = controller.settings.keyboardLayout.resolved() == .azerty
        VStack(spacing: 0) {
            ToolbarView(controller: controller)
                .frame(height: isAzerty ? KeyboardStyle.azertyToolbarHeight : KeyboardStyle.toolbarHeight)
            Group {
                switch controller.phase {
                case .idle:
                    switch controller.panel {
                    case .keys: KeysView(controller: controller)
                    case .enhance: ActionGrid(controller: controller, title: "Enhance", actions: WritingAction.enhance)
                    case .translate: ActionGrid(controller: controller, title: "Translate", actions: WritingAction.translate)
                    case .emoji: EmojiPanel(controller: controller)
                    case .models: KeyboardModelsPanel(controller: controller)
                    }
                default:
                    ResultPanel(controller: controller)
                }
            }
            .frame(height: isAzerty ? KeyboardStyle.azertyKeysHeight : KeyboardStyle.keysHeight)
        }
        .padding(.bottom, isAzerty ? 0 : KeyboardStyle.bottomInset)
    }
}

// MARK: Toolbar

struct ToolbarView: View {
    @ObservedObject var controller: KeyboardController
    private var nativeStrip: Bool { controller.settings.keyboardLayout.resolved() == .azerty }

    var body: some View {
        HStack(spacing: 8) {
            if let notice = controller.liveNotice {
                LiveNoticeView(controller: controller, notice: notice)
            } else {
                Button { controller.run(.fix) } label: {
                    HStack(spacing: 5) {
                        if controller.engineStatus == .loading && !controller.settings.useAppleIntelligenceForFix {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: WritingAction.fix.symbol)
                        }
                        Text("Fix").fontWeight(nativeStrip ? .regular : .semibold)
                    }
                    .padding(.horizontal, nativeStrip ? 5 : 12)
                    .frame(maxWidth: nativeStrip && controller.suggestions.isEmpty ? .infinity : nil)
                    .padding(.vertical, nativeStrip ? 4 : 7)
                    .background(Capsule().fill(nativeStrip ? Color.black.opacity(0.01) : KeyboardStyle.accent))
                    .contentShape(Rectangle())
                    .foregroundStyle(nativeStrip ? Color.primary : .white)
                }
                .accessibilityIdentifier("kb.fix")
                if nativeStrip { Divider().frame(height: 22) }

                if !controller.suggestions.isEmpty {
                    ForEach(Array(controller.suggestions.enumerated()), id: \.offset) { index, word in
                        Button { controller.applySuggestion(word) } label: {
                            Text(word).lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("kb.suggestion.\(index)")
                        if index < controller.suggestions.count - 1 { Divider().frame(height: 22) }
                    }
                } else {
                    chip("Enhance", symbol: "wand.and.stars", id: "kb.enhance") { controller.openPanel(.enhance) }
                    if nativeStrip { Divider().frame(height: 22) }
                    chip("Translate", symbol: "globe", id: "kb.translate") { controller.openPanel(.translate) }
                    if !nativeStrip { Spacer(minLength: 0) }
                }
                if case .idle = controller.phase {
                    Button { controller.openPanel(controller.panel == .models ? .keys : .models) } label: {
                        Image(systemName: "cpu")
                            .frame(width: 34, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("AI models")
                    .accessibilityIdentifier("kb.models")
                }
                if controller.canUndo {
                    Button { controller.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .accessibilityIdentifier("kb.undo")
                }
            }
        }
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
    }

    private func chip(_ title: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
                .padding(.horizontal, nativeStrip ? 5 : 9)
                .frame(maxWidth: nativeStrip ? .infinity : nil)
                .padding(.vertical, nativeStrip ? 4 : 7)
                .background(Capsule().fill(nativeStrip ? Color.black.opacity(0.01) : KeyboardStyle.letterKey.opacity(0.8)))
                .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }
}

struct KeyboardModelsPanel: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        let usesApple = controller.settings.useAppleIntelligenceForFix
        let selectedLocal = controller.host?.selectedLocalModelName
        let loadedLocal = controller.engineStatus == .ready ? controller.host?.localModelName : nil
        let local = loadedLocal ?? selectedLocal ?? "No downloaded model"
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("AI models").font(.headline)
                Spacer()
                Button { controller.panel = .keys } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel("Back to keyboard")
                .accessibilityIdentifier("kb.models.close")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    modelRow("Fix", name: usesApple ? "Apple Intelligence" : local, id: "kb.models.fix")
                    if usesApple {
                        if let reason = controller.host?.appleFixUnavailableReason {
                            Text(reason).font(.caption).foregroundStyle(.secondary)
                        }
                        modelRow("Other tools and fallback", name: local, id: "kb.models.local")
                    } else {
                        Text("Also used for Enhance, Translate, and corrections while typing.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let selectedLocal, let loadedLocal, selectedLocal != loadedLocal {
                        Text("Selected in Lokey: \(selectedLocal)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Change these in Lokey → AI model.").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
    }

    private func modelRow(_ title: String, name: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(name).font(.subheadline.weight(.semibold)).accessibilityIdentifier(id)
        }
    }
}

struct LiveNoticeView: View {
    @ObservedObject var controller: KeyboardController
    let notice: KeyboardController.LiveNotice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.kind == .applied ? "checkmark.circle.fill" : "lightbulb.fill")
                .foregroundStyle(notice.kind == .applied ? KeyboardStyle.inserted : .orange)
            Text(notice.kind == .applied ? "Fixed: \(notice.summary)" : notice.corrected)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("kb.live.text")
            Button(notice.kind == .applied ? "Undo" : "Apply") { controller.resolveLiveNotice() }
                .fontWeight(.semibold)
                .accessibilityIdentifier("kb.live.resolve")
            Button { controller.dismissLiveNotice() } label: { Image(systemName: "xmark") }
                .accessibilityIdentifier("kb.live.dismiss")
        }
    }
}

// MARK: Result panel

struct ResultPanel: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Button { controller.dismissPhase() } label: { Image(systemName: "xmark.circle.fill").font(.title3) }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("kb.close")
            }
            if let fallback = controller.fixFallback {
                fallbackNotice(fallback)
            }
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(KeyboardStyle.previewBackground))
            buttons
        }
        .padding(10)
    }

    private var title: String {
        switch controller.phase {
        case .working(let action, _), .result(let action, _): return action.title
        case .message: return controller.fixFallback == nil ? Brand.name : WritingAction.fix.title
        case .idle: return ""
        }
    }

    private func fallbackNotice(_ fallback: KeyboardController.FixFallback) -> some View {
        let detail: String?
        switch (fallback, controller.phase) {
        case (.preparing, .working): detail = "Looking for a local model…"
        case (.preparing, _): detail = nil
        case (.localModel(let name), .working): detail = "Trying \(name) on-device…"
        case (.localModel(let name), .result): detail = "Corrected with \(name) on-device"
        case (.localModel(let name), _): detail = "Tried \(name) on-device"
        }
        return VStack(alignment: .leading, spacing: 2) {
            Label("Apple Intelligence couldn’t complete Fix", systemImage: "arrow.left.arrow.right")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("kb.fixFallback")
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("kb.fixFallbackModel")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(KeyboardStyle.previewBackground))
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .working(_, let partial):
            HStack(alignment: .top) {
                Text(partial.isEmpty ? "Thinking on-device…" : partial)
                    .foregroundStyle(partial.isEmpty ? .secondary : .primary)
                Spacer()
                ProgressView()
            }
            .accessibilityIdentifier("kb.working")
        case .result(let action, let result):
            if action.group == .translate {
                VStack(alignment: .leading, spacing: 8) {
                    previewLabel("Translation")
                    proposal(Text(result.output), result: result)
                    Divider()
                    previewLabel("Original")
                    Text(result.original)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("kb.original")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("Removed").strikethrough().foregroundStyle(KeyboardStyle.previewRemoved)
                        Text("Added").bold().foregroundStyle(KeyboardStyle.previewAdded)
                    }
                    .font(.caption2)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("kb.changeLegend")
                    proposal(Text(Self.attributed(result.segments)), result: result)
                }
            }
        case .message(let message):
            Text(message).accessibilityIdentifier("kb.message")
        case .idle:
            EmptyView()
        }
    }

    private func previewLabel(_ title: String) -> some View {
        Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private func proposal(_ text: Text, result: AssistantResult) -> some View {
        VStack(alignment: .leading, spacing: 0) { text }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(result.output)
            .accessibilityIdentifier("kb.result")
    }

    @ViewBuilder private var buttons: some View {
        switch controller.phase {
        case .result(let action, let result):
            HStack {
                let seconds = controller.lastWaitSeconds ?? result.stats.totalSeconds
                VStack(alignment: .leading, spacing: 1) {
                    Text(seconds > 0 ? String(format: "%.2fs on-device", seconds) : "")
                    if action == .fix && controller.settings.useAppleIntelligenceForFix && controller.fixFallback == nil {
                        Text("Apple Intelligence").accessibilityIdentifier("kb.appleFix")
                    } else if controller.fixFallback == nil, let local = controller.host?.localModelName {
                        Text(local).accessibilityIdentifier("kb.localModel")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { controller.retry() }.accessibilityIdentifier("kb.retry")
                Button { controller.applyResult() } label: {
                    Text("Apply").fontWeight(.semibold).padding(.horizontal, 18).padding(.vertical, 7)
                        .background(Capsule().fill(KeyboardStyle.accent)).foregroundStyle(.white)
                }
                .accessibilityIdentifier("kb.apply")
            }
        case .message:
            HStack { Spacer(); Button("OK") { controller.dismissPhase() }.accessibilityIdentifier("kb.ok") }
        default:
            EmptyView()
        }
    }

    private static func attributed(_ segments: [TextDiff.Segment]) -> AttributedString {
        var out = AttributedString()
        var previous: TextDiff.Segment?
        for segment in segments {
            if let previous, previous.kind == .removed, segment.kind == .inserted,
               previous.text.last?.isWhitespace == false, segment.text.first?.isWhitespace == false {
                out += AttributedString("\u{2009}")
            }
            let visible = segment.kind == .equal ? segment.text : visibleChange(segment.text)
            var part = AttributedString(visible)
            switch segment.kind {
            case .equal:
                break
            case .inserted:
                part.foregroundColor = KeyboardStyle.previewAdded
                part.font = .body.bold()
            case .removed:
                part.foregroundColor = KeyboardStyle.previewRemoved
                part.strikethroughStyle = .single
            }
            out += part
            previous = segment
        }
        return out
    }

    private static func visibleChange(_ text: String) -> String {
        guard text.allSatisfy(\.isWhitespace) else { return text }
        return text.map { character in
            if character.isNewline { return "↵\n" }
            return character == "\t" ? "⇥" : "·"
        }.joined()
    }
}

// MARK: Action grid

struct ActionGrid: View {
    @ObservedObject var controller: KeyboardController
    let title: String
    let actions: [WritingAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { controller.panel = .keys } label: { Label("Back", systemImage: "chevron.left") }
                    .accessibilityIdentifier("kb.back")
                Spacer()
                Text(title).font(.headline)
                Spacer()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(actions) { action in
                    Button { controller.run(action) } label: {
                        Label(action.title, systemImage: action.symbol)
                            .frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(RoundedRectangle(cornerRadius: 9).fill(KeyboardStyle.letterKey))
                            .shadow(color: KeyboardStyle.shadow, radius: 0, y: 1)
                    }
                    .accessibilityIdentifier("kb.action.\(action.id)")
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.primary)
        .padding(10)
    }
}
#endif
