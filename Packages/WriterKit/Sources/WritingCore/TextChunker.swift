import Foundation

/// Splits long text into sentence-aligned chunks so each model call stays short
/// (predictable latency, small context in the keyboard) while preserving the
/// exact whitespace between chunks.
public enum TextChunker {
    public struct Chunk: Equatable, Sendable {
        /// Leading whitespace kept verbatim (not sent to the model).
        public var leading: String
        public var body: String
        /// Trailing whitespace kept verbatim.
        public var trailing: String
    }

    public static let sentenceTerminators: Set<Character> = [".", "!", "?", "…"]

    /// Sentence ranges: a sentence ends after a run of terminators (plus closing quotes/brackets)
    /// followed by whitespace, or at a newline.
    public static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            current.append(ch)
            if ch == "\n" {
                result.append(current); current = ""
            } else if sentenceTerminators.contains(ch) {
                var j = i + 1
                while j < chars.count, sentenceTerminators.contains(chars[j]) || "\"')]”’".contains(chars[j]) {
                    current.append(chars[j]); j += 1
                }
                if j >= chars.count || chars[j].isWhitespace {
                    while j < chars.count, chars[j] == " " || chars[j] == "\t" {
                        current.append(chars[j]); j += 1
                    }
                    result.append(current); current = ""
                }
                i = j
                continue
            }
            i += 1
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Groups sentences into chunks of at most `maxCharacters` (a single longer sentence
    /// becomes its own chunk).
    public static func chunks(_ text: String, maxCharacters: Int = 400) -> [Chunk] {
        var groups: [String] = []
        var current = ""
        for sentence in sentences(text) {
            if !current.isEmpty && (current.count + sentence.count > maxCharacters || current.hasSuffix("\n")) {
                groups.append(current); current = ""
            }
            current += sentence
        }
        if !current.isEmpty { groups.append(current) }
        return groups.map { group in
            let leading = String(group.prefix(while: { $0.isWhitespace }))
            let rest = group.dropFirst(leading.count)
            let trailingCount = rest.reversed().prefix(while: { $0.isWhitespace }).count
            return Chunk(leading: leading, body: String(rest.dropLast(trailingCount)), trailing: String(rest.suffix(trailingCount)))
        }
    }
}
