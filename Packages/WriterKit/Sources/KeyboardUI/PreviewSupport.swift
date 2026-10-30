#if canImport(UIKit)
import SwiftUI
import WritingCore

/// A `TextDocument` the in-app keyboard preview (and UI tests) can type into and observe.
public final class ObservableTextDocument: ObservableObject, TextDocument {
    @Published public private(set) var text: String = ""
    private let base = SimulatedTextDocument()

    public init() {}

    public var cursor: Int { base.cursor }
    public var documentContextBeforeInput: String? { base.documentContextBeforeInput }
    public var documentContextAfterInput: String? { base.documentContextAfterInput }
    public var selectedText: String? { nil }

    public func insertText(_ s: String) { base.insertText(s); sync() }
    public func deleteBackward() { base.deleteBackward(); sync() }
    public func adjustTextPosition(byCharacterOffset offset: Int) { base.adjustTextPosition(byCharacterOffset: offset); sync() }

    public func clear() {
        base.adjustTextPosition(byCharacterOffset: base.text.count)
        while base.cursor > 0 { base.deleteBackward() }
        sync()
    }

    private func sync() { text = base.text }
}

/// Host used by the in-app preview: behaves like a keyboard with Full Access in a plain text field.
@MainActor
public final class PreviewKeyboardHost: KeyboardHost {
    public init() {}
    public var hasFullAccess: Bool { true }
    public var needsInputModeSwitchKey: Bool { false }
    public var returnKeyTitle: String { "return" }
    public var autocapitalizesSentences: Bool { true }
    public func advanceToNextInputMode() {}
    public func playInputClick() {}
}

public extension KeyboardController {
    /// Call when the host reports a text change it did not originate (cursor moved, app edited text).
    func textDidChange() {
        objectWillChange.send()
        refreshAfterExternalChange()
    }
}
#endif
