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
    var leadingSpace: CGFloat = 0
    var trailingSpace: CGFloat = 0
}

enum KeyboardLayouts {
    static func rows(for layer: KeyboardController.Layer, layout: KeyboardLayout, showGlobe: Bool) -> [[KeySpec]] {
        if layout == .azerty { return azertyRows(for: layer, showGlobe: showGlobe) }
        // The bottom row fills the same ten columns as the top letter row.
        let bottom: [KeySpec] = [
            KeySpec(kind: .layer(layer == .letters ? .numbers : .letters), width: 1.25),
            KeySpec(kind: .emoji, width: 1.25),
        ] + (showGlobe ? [KeySpec(kind: .globe, width: 1.25)] : []) + [
            KeySpec(kind: .space, width: showGlobe ? 3.5 : 4.75),
            KeySpec(kind: .character("."), width: 1),
            KeySpec(kind: .newline, width: 1.75),
        ]
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

    private static func chars(_ text: String, width: CGFloat = 1) -> [KeySpec] {
        text.map { KeySpec(kind: .character(String($0)), width: width) }
    }

    private static func azertyRows(for layer: KeyboardController.Layer, showGlobe: Bool) -> [[KeySpec]] {
        let bottom = [
            KeySpec(kind: .layer(layer == .letters ? .numbers : .letters), width: 1.25),
            KeySpec(kind: .emoji, width: 1.25),
        ] + (showGlobe ? [KeySpec(kind: .globe, width: 1.25)] : []) + [
            KeySpec(kind: .space, width: showGlobe ? 3.75 : 5),
            KeySpec(kind: .newline, width: 2.5),
        ]
        // On all three pages, the outer keys are 1.3 columns wide and the
        // middle group starts 1.5 columns in. Its five punctuation keys
        // occupy the same seven columns as the seven letter keys.
        let left = KeySpec(kind: layer == .letters ? .shift : .symbolsToggle, width: 1.3, trailingSpace: 0.2)
        let right = KeySpec(kind: .delete, width: 1.3, leadingSpace: 0.2)
        if layer == .letters {
            let letters = KeyboardLayout.azerty.letterRows
            return [
                chars(letters[0]), chars(letters[1]),
                [left] + chars(letters[2]) + [right],
                bottom,
            ]
        }
        return [
            chars(layer == .numbers ? "1234567890" : "[]{}#%^*+="),
            chars(layer == .numbers ? "-/:;()€&@\"" : "_\\|~<>$£¥•"),
            [left] + chars(".,?!'", width: 1.4) + [right],
            bottom,
        ]
    }
}

struct KeysView: View {
    @ObservedObject var controller: KeyboardController

    var body: some View {
        GeometryReader { geo in
            let layout = controller.settings.keyboardLayout.resolved()
            let rows = KeyboardLayouts.rows(for: controller.layer, layout: layout, showGlobe: controller.host?.needsInputModeSwitchKey ?? false)
            let rowWidth = geo.size.width - (layout == .azerty ? 7 : 0)
            let pitch = rowWidth / 10
            let halfKeySpacing = KeyboardStyle.keySpacing / 2
            let halfRowSpacing = KeyboardStyle.rowSpacing / 2
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    // Split the visual gaps between neighboring keys so taps there still type.
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, spec in
                            KeyButton(controller: controller, spec: spec,
                                      width: spec.width * pitch - KeyboardStyle.keySpacing,
                                      hitPadding: EdgeInsets(
                                        top: rowIndex == 0 ? 0 : halfRowSpacing,
                                        leading: halfKeySpacing + spec.leadingSpace * pitch,
                                        bottom: rowIndex == rows.count - 1 ? 0 : halfRowSpacing,
                                        trailing: halfKeySpacing + spec.trailingSpace * pitch
                                      ))
                        }
                    }
                }
            }
            .frame(width: geo.size.width)
            .padding(.top, layout == .azerty ? KeyboardStyle.azertyTopInset : 8)
        }
    }
}

struct KeyButton: View {
    @ObservedObject var controller: KeyboardController
    let spec: KeySpec
    let width: CGFloat
    let hitPadding: EdgeInsets
    /// Resets automatically when the touch ends *or is cancelled*, which also stops delete repeat.
    @GestureState private var pressed = false
    @State private var repeatTask: Task<Void, Never>?
    @State private var lastShiftTap: Date?
    @State private var spacePressStartedAt: Date?
    @State private var spaceDragSteps = 0
    private let cursorHoldDuration: TimeInterval = 0.45

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: isAzerty ? 8.5 : 5)
                .fill(pressed ? KeyboardStyle.pressedKey : background)
                .shadow(color: isAzerty ? .clear : KeyboardStyle.shadow, radius: 0, x: 0, y: 1)
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
        .padding(hitPadding)
        // SwiftUI needs a rendered surface to receive quick taps in the padding.
        .background(Color.black.opacity(0.01))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressed) { _, state, _ in state = true }
                .onChanged { value in
                    if spec.kind == .space { updateSpaceDrag(value) }
                }
                .onEnded { value in
                    // Delete acts on touch-down (see onChange); every other key on release.
                    if spec.kind == .space {
                        let held = spacePressStartedAt.map { value.time.timeIntervalSince($0) >= cursorHoldDuration } ?? false
                        if held { updateSpaceDrag(value) } else { perform() }
                        resetSpaceDrag()
                    } else if spec.kind != .delete {
                        perform()
                    }
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
            if spec.kind == .delete {
                if isPressed { startDeleteRepeat() } else { stopDeleteRepeat() }
            } else if spec.kind == .space, !isPressed {
                resetSpaceDrag()
            }
        }
        .onDisappear { stopDeleteRepeat() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
        .accessibilityAction { perform() }
    }

    private var isAzerty: Bool { controller.settings.keyboardLayout.resolved() == .azerty }

    private var background: Color {
        if isAzerty { return KeyboardStyle.azertyKey }
        switch spec.kind {
        case .character, .space: return KeyboardStyle.letterKey
        case .shift where controller.shift != .off: return KeyboardStyle.letterKey
        default: return KeyboardStyle.specialKey
        }
    }

    private func updateSpaceDrag(_ value: DragGesture.Value) {
        if spacePressStartedAt == nil { spacePressStartedAt = value.time }
        guard let startedAt = spacePressStartedAt,
              value.time.timeIntervalSince(startedAt) >= cursorHoldDuration else { return }
        let steps = Int(value.translation.width / 12)
        controller.moveTypingCursor(by: steps - spaceDragSteps)
        spaceDragSteps = steps
    }

    private func resetSpaceDrag() {
        spacePressStartedAt = nil
        spaceDragSteps = 0
    }

    private func display(_ c: String) -> String {
        controller.layer == .letters && controller.shift != .off ? c.uppercased() : c
    }

    @ViewBuilder private var label: some View {
        switch spec.kind {
        case .character(let c):
            Text(display(c)).font(.system(size: isAzerty ? 22 : 23))
                .offset(y: isAzerty ? -1 : 0)
        case .shift:
            Image(systemName: controller.shift == .locked ? "capslock.fill" : controller.shift == .once ? "shift.fill" : "shift")
                .font(.system(size: isAzerty ? 21 : 17))
        case .delete: Image(systemName: "delete.left").font(.system(size: isAzerty ? 21 : 17))
        case .space:
            if isAzerty {
                Text("FR EN")
                    .font(.system(size: 11, weight: .medium))
                    .fontWidth(.compressed)
                    .foregroundStyle(.primary.opacity(0.30))
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            } else {
                Text("space").font(.system(size: 16))
            }
        case .newline:
            let title = controller.host?.returnKeyTitle ?? "return"
            if title == "return", isAzerty {
                Image(systemName: "return").font(.system(size: 19.5))
            } else {
                Text(title).font(.system(size: 16))
            }
        case .layer(let target): Text(target == .letters ? "ABC" : "123").font(.system(size: 16))
        case .globe: Image(systemName: "globe")
        case .symbolsToggle:
            Text(controller.layer == .symbols ? "123" : "#+=")
                .font(.system(size: isAzerty && controller.layer == .numbers ? 14 : 16))
        case .emoji:
            if isAzerty {
                EmojiKeyFace().fill(.primary, style: FillStyle(eoFill: true))
                    .frame(width: 19, height: 19)
            } else {
                Image(systemName: "face.smiling").font(.system(size: 17))
            }
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

private struct EmojiKeyFace: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 19
        var path = Path(ellipseIn: rect)
        for x in [5.0, 11.5] {
            path.addEllipse(in: CGRect(x: x * unit, y: 5 * unit, width: 2.5 * unit, height: 2.5 * unit))
        }
        path.move(to: CGPoint(x: 4.5 * unit, y: 10 * unit))
        path.addQuadCurve(to: CGPoint(x: 14.5 * unit, y: 10 * unit), control: CGPoint(x: 9.5 * unit, y: 11.5 * unit))
        path.addQuadCurve(to: CGPoint(x: 4.5 * unit, y: 10 * unit), control: CGPoint(x: 9.5 * unit, y: 19 * unit))
        path.closeSubpath()
        return path
    }
}
#endif
