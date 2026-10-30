import Foundation

/// The subset of `UITextDocumentProxy` the keyboard needs. Abstracted so that editing
/// logic is unit-testable and so the in-app keyboard preview can drive a simulated document.
public protocol TextDocument: AnyObject {
    var documentContextBeforeInput: String? { get }
    var documentContextAfterInput: String? { get }
    var selectedText: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
}

/// One primitive edit against a `TextDocument`, relative to the current cursor.
public enum EditStep: Equatable, Sendable {
    case moveCursor(Int)
    case deleteBackward(Int)
    case insert(String)
}

public enum EditPlanner {
    /// Plans the replacement of `original` with `replacement`, where the document reads
    /// `original + tail` immediately before the cursor.
    ///
    /// Only the differing middle is deleted and re-typed. Cursor moves are used only across text made
    /// of single-UTF-16 characters, where "character offset" means the same thing in every host app;
    /// otherwise the plan deletes back to the edit and re-inserts the tail.
    public static func plan(original: String, replacement: String, tail: String = "") -> [EditStep] {
        if original == replacement { return [] }
        let o = Array(original), r = Array(replacement)
        var prefix = 0
        while prefix < o.count, prefix < r.count, o[prefix] == r[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < o.count - prefix, suffix < r.count - prefix,
              o[o.count - 1 - suffix] == r[r.count - 1 - suffix] { suffix += 1 }

        let oldMiddle = o.count - prefix - suffix
        let newMiddle = String(r[prefix..<(r.count - suffix)])
        let keptSuffix = String(o[(o.count - suffix)...]) + tail

        var steps: [EditStep] = []
        if keptSuffix.isEmpty {
            if oldMiddle > 0 { steps.append(.deleteBackward(oldMiddle)) }
            if !newMiddle.isEmpty { steps.append(.insert(newMiddle)) }
        } else if isOffsetSafe(keptSuffix) {
            steps.append(.moveCursor(-keptSuffix.count))
            if oldMiddle > 0 { steps.append(.deleteBackward(oldMiddle)) }
            if !newMiddle.isEmpty { steps.append(.insert(newMiddle)) }
            steps.append(.moveCursor(keptSuffix.count))
        } else {
            steps.append(.deleteBackward(keptSuffix.count + oldMiddle))
            steps.append(.insert(newMiddle + keptSuffix))
        }
        return steps
    }

    /// True when every character is a single UTF-16 unit, so character and UTF-16 offsets agree.
    public static func isOffsetSafe(_ s: String) -> Bool {
        s.count == s.utf16.count
    }

    public static func apply(_ steps: [EditStep], to document: TextDocument) {
        for step in steps {
            switch step {
            case .moveCursor(let offset):
                if offset != 0 { document.adjustTextPosition(byCharacterOffset: offset) }
            case .deleteBackward(let count):
                for _ in 0..<count { document.deleteBackward() }
            case .insert(let text):
                document.insertText(text)
            }
        }
    }
}

/// An in-memory `TextDocument` with grapheme-based cursor semantics. Used by tests and
/// by the in-app keyboard preview.
public final class SimulatedTextDocument: TextDocument {
    public private(set) var text: String
    /// Cursor position in Characters.
    public private(set) var cursor: Int
    public var contextLimit: Int?

    public init(text: String = "", cursor: Int? = nil, contextLimit: Int? = nil) {
        self.text = text
        self.cursor = cursor ?? text.count
        self.contextLimit = contextLimit
    }

    public var documentContextBeforeInput: String? {
        let before = String(text.prefix(cursor))
        if let limit = contextLimit { return String(before.suffix(limit)) }
        return before
    }

    public var documentContextAfterInput: String? {
        let after = String(text.dropFirst(cursor))
        if let limit = contextLimit { return String(after.prefix(limit)) }
        return after
    }

    public var selectedText: String? { nil }

    public func insertText(_ s: String) {
        let idx = text.index(text.startIndex, offsetBy: cursor)
        text.insert(contentsOf: s, at: idx)
        cursor += s.count
    }

    public func deleteBackward() {
        guard cursor > 0 else { return }
        let idx = text.index(text.startIndex, offsetBy: cursor - 1)
        text.remove(at: idx)
        cursor -= 1
    }

    public func adjustTextPosition(byCharacterOffset offset: Int) {
        cursor = min(max(0, cursor + offset), text.count)
    }
}
