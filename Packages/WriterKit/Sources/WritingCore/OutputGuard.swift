import Foundation

/// Rejects model outputs that look like an answer to the text rather than an edit of it.
///
/// Small local models sometimes reply to "can you explain me how it works?" instead of
/// correcting it. The guard is deterministic and cheap, and a rejection simply means
/// "no suggestion": the user's text is never replaced by something unrelated.
public struct OutputGuard: Sendable {
    public enum Verdict: Equatable, Sendable {
        case accepted
        case rejected(Reason)

        public var isAccepted: Bool { self == .accepted }
    }

    public enum Reason: String, Equatable, Sendable {
        case empty, length, newlines, opener, similarity, retention, leakage
    }

    public let config: GuardConfig
    public let assistantOpeners: [String]
    /// Words (4+ letters) from the prompt's few-shot examples. A small model sometimes copies
    /// them into the user's text ("I want to come to Café Luna."); new words from this set are rejected.
    public let exampleWords: Set<String>

    public init(config: GuardConfig, assistantOpeners: [String], exampleWords: Set<String> = []) {
        self.config = config
        self.assistantOpeners = assistantOpeners
        self.exampleWords = exampleWords
    }

    public init(library: PromptLibrary, action: String) throws {
        let examples = library.actions[action]?.examples ?? []
        let words = examples.flatMap { Similarity.words($0.input + " " + $0.output) }.filter { $0.count >= 4 }
        self.init(config: try library.guardConfig(for: action), assistantOpeners: library.assistantOpeners,
                  exampleWords: Set(words))
    }

    public func evaluate(source: String, output: String) -> Verdict {
        if output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .rejected(.empty) }
        // Python's len() counts code points; match it.
        let ratio = Double(output.unicodeScalars.count) / Double(max(1, source.unicodeScalars.count))
        if ratio < config.minLengthRatio || ratio > config.maxLengthRatio { return .rejected(.length) }
        if !config.allowNewLines && newlineCount(output) > newlineCount(source) { return .rejected(.newlines) }
        if config.rejectAssistantOpeners {
            let o = normalizedStart(output), s = normalizedStart(source)
            for opener in assistantOpeners where o.hasPrefix(opener) && !s.hasPrefix(opener) {
                return .rejected(.opener)
            }
        }
        if Similarity.ratio(source, output) < config.minSimilarity { return .rejected(.similarity) }
        if Similarity.wordRetention(source: source, output: output) < config.minWordRetention {
            return .rejected(.retention)
        }
        if config.minWordRetention > 0, !Similarity.leakedWords(source: source, output: output, exampleWords: exampleWords).isEmpty {
            return .rejected(.leakage)
        }
        return .accepted
    }

    private func newlineCount(_ s: String) -> Int {
        s.unicodeScalars.filter { $0 == "\n" }.count
    }

    private func normalizedStart(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
    }
}
