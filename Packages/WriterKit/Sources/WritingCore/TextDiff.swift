import Foundation

/// Word-level diff used to highlight what a correction changed.
public enum TextDiff {
    public enum Kind: String, Sendable, Equatable { case equal, removed, inserted }

    public struct Segment: Sendable, Equatable {
        public var kind: Kind
        public var text: String
        public init(_ kind: Kind, _ text: String) { self.kind = kind; self.text = text }
    }

    /// Splits into words and the whitespace/punctuation around them, keeping every character,
    /// so joining the tokens reproduces the input exactly.
    public static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsWord: Bool?
        for ch in s {
            let isWord = ch.isLetter || ch.isNumber || ch == "'" || ch == "\u{2019}"
            if isWord {
                if currentIsWord == false { tokens.append(current); current = "" }
                current.append(ch)
                currentIsWord = true
            } else {
                if !current.isEmpty { tokens.append(current) }
                tokens.append(String(ch))
                current = ""
                currentIsWord = false
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// LCS diff over tokens, with adjacent segments of the same kind merged.
    public static func diff(_ old: String, _ new: String) -> [Segment] {
        let a = tokenize(old), b = tokenize(new)
        let n = a.count, m = b.count
        var lcs = [[Int]](repeating: [Int](repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
                }
            }
        }
        var segments: [Segment] = []
        func push(_ kind: Kind, _ text: String) {
            if let last = segments.last, last.kind == kind {
                segments[segments.count - 1].text += text
            } else {
                segments.append(Segment(kind, text))
            }
        }
        var i = 0, j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                push(.equal, a[i]); i += 1; j += 1
            } else if lcs[i + 1][j] >= lcs[i][j + 1] {
                push(.removed, a[i]); i += 1
            } else {
                push(.inserted, b[j]); j += 1
            }
        }
        while i < n { push(.removed, a[i]); i += 1 }
        while j < m { push(.inserted, b[j]); j += 1 }
        return segments
    }

    /// Human-readable list of edits, e.g. ["their → they're", "+ ?"].
    public static func changes(_ old: String, _ new: String) -> [String] {
        let segments = diff(old, new)
        var result: [String] = []
        var idx = 0
        while idx < segments.count {
            let seg = segments[idx]
            switch seg.kind {
            case .equal:
                break
            case .removed:
                if idx + 1 < segments.count, segments[idx + 1].kind == .inserted {
                    result.append("\(seg.text.trimmed) → \(segments[idx + 1].text.trimmed)")
                    idx += 1
                } else {
                    result.append("− \(seg.text.trimmed)")
                }
            case .inserted:
                result.append("+ \(seg.text.trimmed)")
            }
            idx += 1
        }
        return result.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0 != "+ " && $0 != "− " }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
