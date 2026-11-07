#if canImport(UIKit)
import SwiftUI
import UIKit
import WritingCore

enum KeyKind: Hashable {
    case character(String)
    case shift, delete, space, newline, layer(KeyboardController.Layer), globe, symbolsToggle, emoji
}

struct KeySpec: Hashable {
    var kind: KeyKind
    /// Width in units of a letter key.
    var width: CGFloat = 1
}

enum KeyboardLayouts {
    static func rows(for layer: KeyboardController.Layer, layout: KeyboardLayout, showGlobe: Bool) -> [[KeySpec]] {
        // Every row adds up to 10 key units.
        let bottom: [KeySpec] = [
            KeySpec(kind: .layer(layer == .letters ? .numbers : .letters), width: 1.25),
            KeySpec(kind: .emoji, width: 1.25),
        ] + (showGlobe ? [KeySpec(kind: .globe, width: 1.25)] : []) + [
            KeySpec(kind: .space, width: showGlobe ? 3.5 : 4.75),
            KeySpec(kind: .character("."), width: 1),
            KeySpec(kind: .newline, width: 1.75),
        ]
        func chars(_ s: String) -> [KeySpec] { s.map { KeySpec(kind: .character(String($0))) } }
        switch layer {
        case .letters:
            let letters = layout.letterRows
            return [chars(letters[0]), chars(letters[1]),
                    [KeySpec(kind: .shift, width: 1.4)] + chars(letters[2]) + [KeySpec(kind: .delete, width: 1.4)],
                    bottom]
        case .numbers:
            return [chars("1234567890"), chars("-/:;()$&@\""),
                    [KeySpec(kind: .symbolsToggle, width: 1.4)] + chars(".,?!'") + [KeySpec(kind: .delete, width: 1.4)],
                    bottom]
        case .symbols:
            return [chars("[]{}#%^*+="), chars("_\\|~<>€£¥•"),
                    [KeySpec(kind: .symbolsToggle, width: 1.4)] + chars(".,?!'") + [KeySpec(kind: .delete, width: 1.4)],
                    bottom]
        }
    }
}

struct KeysView: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        GeometryReader { geo in
            let rows = KeyboardLayouts.rows(for: controller.layer, layout: controller.settings.keyboardLayout, showGlobe: controller.host?.needsInputModeSwitchKey ?? false)
            let unit = (geo.size.width - KeyboardStyle.sidePadding * 2 - KeyboardStyle.keySpacing * 9) / 10
            VStack(spacing: KeyboardStyle.rowSpacing) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: KeyboardStyle.keySpacing) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, spec in
                            KeyButton(controller: controller, spec: spec,
                                      width: spec.width * unit + (spec.width - 1) * KeyboardStyle.keySpacing)
                        }
                    }
                }
            }
            .frame(width: geo.size.width)
            .padding(.top, 8)
        }
    }
}

struct KeyButton: View {
    @ObservedObject var controller: KeyboardController
    let spec: KeySpec
    let width: CGFloat
    /// Resets automatically when the touch ends *or is cancelled*, which also stops delete repeat.
    @GestureState private var pressed = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var lastShiftTap: Date?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(pressed ? KeyboardStyle.pressedKey : background)
                .shadow(color: KeyboardStyle.shadow, radius: 0, x: 0, y: 1)
            label
        }
        .frame(width: width, height: KeyboardStyle.keyHeight)
        .overlay(alignment: .top) {
            if pressed, case .character(let c) = spec.kind {
                Text(display(c))
                    .font(.system(size: 32))
                    .frame(width: max(width, 44) + 12, height: 54)
                    .background(RoundedRectangle(cornerRadius: 8).fill(KeyboardStyle.letterKey).shadow(color: KeyboardStyle.shadow, radius: 1))
                    .offset(y: -58)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressed) { _, state, _ in state = true }
                .onEnded { _ in
                    // Delete acts on touch-down (see onChange); every other key on release.
                    if spec.kind != .delete { perform() }
                }
        )
        .contextMenu {
            if case .character(let character) = spec.kind {
                ForEach(KeyboardLayout.alternatives(for: character), id: \.self) { alternative in
                    Button(display(alternative)) { controller.type(alternative) }
                }
            }
        }
        .onChange(of: pressed) { _, isPressed in
            guard spec.kind == .delete else { return }
            if isPressed { startDeleteRepeat() } else { stopDeleteRepeat() }
        }
        .onDisappear { stopDeleteRepeat() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
        .accessibilityAction { perform() }
    }

    private var background: Color {
        switch spec.kind {
        case .character, .space: return KeyboardStyle.letterKey
        case .shift where controller.shift != .off: return KeyboardStyle.letterKey
        default: return KeyboardStyle.specialKey
        }
    }

    private func display(_ c: String) -> String {
        controller.layer == .letters && controller.shift != .off ? c.uppercased() : c
    }

    @ViewBuilder private var label: some View {
        switch spec.kind {
        case .character(let c): Text(display(c)).font(.system(size: 23))
        case .shift: Image(systemName: controller.shift == .locked ? "capslock.fill" : controller.shift == .once ? "shift.fill" : "shift")
        case .delete: Image(systemName: "delete.left")
        case .space: Text("space").font(.system(size: 16))
        case .newline: Text(controller.host?.returnKeyTitle ?? "return").font(.system(size: 16))
        case .layer(let target): Text(target == .letters ? "ABC" : "123").font(.system(size: 16))
        case .globe: Image(systemName: "globe")
        case .symbolsToggle: Text(controller.layer == .symbols ? "123" : "#+=").font(.system(size: 16))
        case .emoji: Image(systemName: "face.smiling")
        }
    }

    private var identifier: String {
        switch spec.kind {
        case .character(let c): return "kb.key.\(c)"
        case .shift: return "kb.shift"
        case .delete: return "kb.delete"
        case .space: return "kb.space"
        case .newline: return "kb.return"
        case .layer: return "kb.layer"
        case .globe: return "kb.globe"
        case .symbolsToggle: return "kb.symbols"
        case .emoji: return "kb.emoji"
        }
    }

    private var accessibilityLabel: String {
        switch spec.kind {
        case .character(let c): return display(c)
        case .shift: return "shift"
        case .delete: return "delete"
        case .space: return "space"
        case .newline: return controller.host?.returnKeyTitle ?? "return"
        case .layer(let target): return target == .letters ? "letters" : "numbers"
        case .globe: return "next keyboard"
        case .symbolsToggle: return "symbols"
        case .emoji: return "emoji"
        }
    }

    private func perform() {
        switch spec.kind {
        case .character(let c): controller.type(c)
        case .shift:
            if let last = lastShiftTap, Date().timeIntervalSince(last) < 0.35 {
                controller.lockShift()
                lastShiftTap = nil
            } else {
                controller.toggleShift()
                lastShiftTap = Date()
            }
        case .delete: controller.backspace()
        case .space: controller.space()
        case .newline: controller.newline()
        case .layer(let target): controller.layer = target
        case .globe: controller.host?.advanceToNextInputMode()
        case .symbolsToggle: controller.layer = controller.layer == .symbols ? .numbers : .symbols
        case .emoji: controller.panel = .emoji
        }
    }

    /// Holding delete: one delete immediately, then repeats, then whole words.
    private func startDeleteRepeat() {
        controller.backspace()
        repeatTask?.cancel()
        repeatTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            var count = 0
            // Bounded, and stops at the start of the text, even if a release is never delivered.
            while !Task.isCancelled, count < 400, !controller.isAtStart {
                if count < 15 { controller.backspace() } else { controller.deleteWord() }
                count += 1
                try? await Task.sleep(nanoseconds: count < 15 ? 80_000_000 : 220_000_000)
            }
        }
    }

    private func stopDeleteRepeat() {
        repeatTask?.cancel()
        repeatTask = nil
    }
}
#endif
