import Foundation

/// A sentence captured for autocorrection, and what followed it when it was captured.
public struct PendingCorrection: Equatable, Sendable {
    /// The sentence, without surrounding whitespace.
    public var original: String
    /// Whitespace typed after it (at least one space or newline).
    public var tail: String

    public init(original: String, tail: String) {
        self.original = original
        self.tail = tail
    }
}

/// Autocorrect-as-you-type: decides when a sentence is finished and how to apply a correction
/// that arrives after the user has kept typing.
public struct LiveCorrectionPolicy: Sendable {
    public var minWords: Int
    public var maxCharacters: Int

    public init(minWords: Int = 3, maxCharacters: Int = 400) {
        self.minWords = minWords
        self.maxCharacters = maxCharacters
    }

    /// Returns the sentence the user just finished: text ending with a terminator (or a line break)
    /// followed by whitespace, which is everything after it before the cursor.
    public func completedSentence(in contextBefore: String) -> PendingCorrection? {
        let tailCount = contextBefore.reversed().prefix(while: { $0.isWhitespace }).count
        guard tailCount > 0 else { return nil }
        let tail = String(contextBefore.suffix(tailCount))
        let body = String(contextBefore.dropLast(tailCount))
        guard let lastChar = body.last else { return nil }

        let endsSentence = TextChunker.sentenceTerminators.contains(lastChar)
            || ("\"')]”’".contains(lastChar) && body.dropLast().last.map { TextChunker.sentenceTerminators.contains($0) } == true)
        guard endsSentence || tail.contains("\n") else { return nil }

        // The sentence starts after the previous sentence boundary.
        let parts = TextChunker.sentences(body)
        guard let last = parts.last else { return nil }
        let sentence = last.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty, sentence.count <= maxCharacters,
              Similarity.words(sentence).count >= minWords else { return nil }
        return PendingCorrection(original: sentence, tail: tail)
    }

    /// Builds the edit that swaps `pending.original` for `corrected`, given the current context.
    /// Returns nil if the sentence was edited meanwhile (never overwrite the user's own changes).
    public func reconcile(_ pending: PendingCorrection, corrected: String, contextBefore: String) -> [EditStep]? {
        let needle = pending.original + pending.tail
        guard let range = contextBefore.range(of: needle, options: .backwards) else { return nil }
        let typedSince = String(contextBefore[range.upperBound...])
        guard typedSince.count <= maxCharacters else { return nil }
        return EditPlanner.plan(original: pending.original, replacement: corrected, tail: pending.tail + typedSince)
    }
}
