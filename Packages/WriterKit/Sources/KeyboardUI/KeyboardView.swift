#if canImport(UIKit)
import SwiftUI
import UIKit
import WritingCore

/// Apple-keyboard-like palette that follows light/dark mode.
enum KeyboardStyle {
    static let keyHeight: CGFloat = 43
    static let rowSpacing: CGFloat = 11
    static let keySpacing: CGFloat = 6
    static let sidePadding: CGFloat = 3
    static let toolbarHeight: CGFloat = 46
    static var keysHeight: CGFloat { keyHeight * 4 + rowSpacing * 3 + 12 }

    static let letterKey = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.42, alpha: 1) : .white })
    static let specialKey = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.27, alpha: 1) : UIColor(red: 0.68, green: 0.70, blue: 0.74, alpha: 1) })
    static let pressedKey = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(white: 0.55, alpha: 1) : UIColor(red: 0.84, green: 0.85, blue: 0.87, alpha: 1) })
    static let shadow = Color.black.opacity(0.3)
    static let accent = Color(red: 0.13, green: 0.55, blue: 0.42)
    static let inserted = Color(red: 0.10, green: 0.62, blue: 0.35)
    static let removed = Color(red: 0.86, green: 0.24, blue: 0.24)
}

public struct KeyboardView: View {
    @ObservedObject var controller: KeyboardController

    public init(controller: KeyboardController) {
        self.controller = controller
    }

    /// Height the host should give the keyboard (toolbar + keys + bottom inset).
    public static var preferredHeight: CGFloat {
        KeyboardStyle.toolbarHeight + KeyboardStyle.keysHeight + 2
    }

    public var body: some View {
        VStack(spacing: 0) {
            ToolbarView(controller: controller)
                .frame(height: KeyboardStyle.toolbarHeight)
            Group {
                switch controller.phase {
                case .idle:
                    switch controller.panel {
                    case .keys: KeysView(controller: controller)
                    case .enhance: ActionGrid(controller: controller, title: "Enhance", actions: WritingAction.enhance)
                    case .translate: ActionGrid(controller: controller, title: "Translate", actions: WritingAction.translate)
                    case .emoji: EmojiPanel(controller: controller)
                    }
                default:
                    ResultPanel(controller: controller)
                }
            }
            .frame(height: KeyboardStyle.keysHeight)
        }
        .padding(.bottom, 2)
    }
}

// MARK: Toolbar

struct ToolbarView: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        HStack(spacing: 8) {
            if let notice = controller.liveNotice {
                LiveNoticeView(controller: controller, notice: notice)
            } else {
                Button { controller.run(.fix) } label: {
                    HStack(spacing: 5) {
                        if controller.engineStatus == .loading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: WritingAction.fix.symbol)
                        }
                        Text("Fix").fontWeight(.semibold)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(KeyboardStyle.accent))
                    .foregroundStyle(.white)
                }
                .accessibilityIdentifier("kb.fix")

                if !controller.suggestions.isEmpty {
                    ForEach(Array(controller.suggestions.enumerated()), id: \.offset) { index, word in
                        Button { controller.applySuggestion(word) } label: {
                            Text(word).lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .accessibilityIdentifier("kb.suggestion.\(index)")
                        if index < controller.suggestions.count - 1 { Divider().frame(height: 22) }
                    }
                } else {
                    chip("Enhance", symbol: "wand.and.stars", id: "kb.enhance") { controller.panel = .enhance }
                    chip("Translate", symbol: "globe", id: "kb.translate") { controller.panel = .translate }
                    chip(WritingAction.ask.title, symbol: WritingAction.ask.symbol, id: "kb.ask") { controller.run(.ask) }
                    Spacer(minLength: 0)
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
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(Capsule().fill(KeyboardStyle.letterKey.opacity(0.8)))
        }
        .accessibilityIdentifier(id)
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
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(KeyboardStyle.letterKey))
            buttons
        }
        .padding(10)
    }

    private var title: String {
        switch controller.phase {
        case .working(let action, _), .result(let action, _): return action.title
        case .message: return Brand.name
        case .idle: return ""
        }
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
        case .result(_, let result):
            Text(Self.attributed(result.segments, showRemoved: result.actionID == WritingAction.fix.id))
                .accessibilityIdentifier("kb.result")
                .accessibilityValue(result.output)
        case .message(let message):
            Text(message).accessibilityIdentifier("kb.message")
        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        switch controller.phase {
        case .result(_, let result):
            HStack {
                let seconds = controller.lastWaitSeconds ?? result.stats.totalSeconds
                Text(seconds > 0 ? String(format: "%.2fs on-device", seconds) : "")
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

    static func attributed(_ segments: [TextDiff.Segment], showRemoved: Bool) -> AttributedString {
        var out = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            switch segment.kind {
            case .equal:
                break
            case .inserted:
                part.foregroundColor = KeyboardStyle.inserted
                part.font = .body.bold()
            case .removed:
                guard showRemoved else { continue }
                part.foregroundColor = KeyboardStyle.removed
                part.strikethroughStyle = .single
            }
            out += part
        }
        return out
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
