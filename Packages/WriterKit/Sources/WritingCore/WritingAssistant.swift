import Foundation

public struct AssistantResult: Sendable, Equatable {
    public var actionID: String
    public var original: String
    /// What we propose. Equals `original` when nothing changed or every chunk was rejected.
    public var output: String
    public var rejectedChunks: Int
    public var segments: [TextDiff.Segment]
    public var stats: GenerationStats

    public var hasChanges: Bool { output != original }
    public var changes: [String] { TextDiff.changes(original, output) }
    /// 1 - similarity between original and output; 0 means unchanged.
    public var changeRatio: Double { 1 - Similarity.ratio(original, output) }
}

/// Runs a writing action end to end: prompt, local generation, cleanup, guard, diff.
public final class WritingAssistant: @unchecked Sendable {
    public let library: PromptLibrary
    public let generator: TextGenerator
    private let preserveCasualWording: Bool
    /// Corrections are made sentence group by sentence group to keep each call short.
    public var fixChunkCharacters = 400
    public var maxInputCharacters = 6_000

    public init(library: PromptLibrary, generator: TextGenerator, preserveCasualWording: Bool = false) {
        self.library = library
        self.generator = generator
        self.preserveCasualWording = preserveCasualWording
    }

    /// Evaluates the fixed part of the prompt for `actionID` so the first request is fast.
    public func prewarm(actionID: String = WritingAction.fix.id) async {
        guard let prompt = try? generator.renderPrompt(library: library, actionID: actionID, text: "") else { return }
        try? await generator.prewarm(prefix: prompt.prefix)
    }

    public func run(actionID: String, text: String,
                    onPartial: (@Sendable (String) -> Void)? = nil) async throws -> AssistantResult {
        let input = String(text.prefix(maxInputCharacters))
        // Text beyond the limit is passed through unchanged, so `original` is always the full input.
        let remainder = String(text.dropFirst(input.count))

        // Keep the outer whitespace verbatim; models trim it.
        let leading = String(input.prefix(while: { $0.isWhitespace }))
        let trailingCount = input.dropFirst(leading.count).reversed().prefix(while: { $0.isWhitespace }).count
        let core = String(input.dropFirst(leading.count).dropLast(trailingCount))
        let trailing = String(input.suffix(trailingCount))

        guard !core.isEmpty else {
            return AssistantResult(actionID: actionID, original: text, output: text, rejectedChunks: 0,
                                   segments: TextDiff.diff(text, text), stats: GenerationStats())
        }

        var stats = GenerationStats()
        var rejected = 0
        var body = ""

        if actionID == WritingAction.fix.id {
            let chunks = TextChunker.chunks(core, maxCharacters: fixChunkCharacters)
            for chunk in chunks {
                try Task.checkCancellation()
                body += chunk.leading
                if chunk.body.isEmpty {
                    body += chunk.trailing
                    continue
                }
                let done = body
                let (generated, s) = try await generate(actionID: actionID, text: chunk.body, budgetFactor: 1.6, extra: 24) { partial in
                    onPartial?(leading + done + partial)
                }
                stats = stats + s
                let endingPreserved = TextChunker.preserveEnding(of: chunk.body, in: generated)
                let registerPreserved = Self.preserveFrenchRegister(of: chunk.body, in: endingPreserved)
                let reactionPreserved = CasualWording.preserveReaction(in: registerPreserved, from: chunk.body)
                let wordingPreserved = preserveCasualWording
                    ? CasualWording.preserve(in: reactionPreserved, from: chunk.body) : reactionPreserved
                let out = TextDiff.preservingApostrophes(from: chunk.body, in: wordingPreserved)
                let outputGuard = try OutputGuard(library: library, action: actionID, text: chunk.body)
                if outputGuard.evaluate(source: chunk.body, output: out).isAccepted {
                    body += out
                } else {
                    body += chunk.body
                    rejected += 1
                }
                body += chunk.trailing
            }
        } else {
            let isGeneration = actionID == WritingAction.ask.id
            let (out, s) = try await generate(actionID: actionID, text: core,
                                              budgetFactor: isGeneration ? 0 : 2.5,
                                              extra: isGeneration ? 400 : 64) { partial in
                onPartial?(leading + partial)
            }
            stats = s
            let outputGuard = try OutputGuard(library: library, action: actionID, text: core)
            if outputGuard.evaluate(source: core, output: out).isAccepted {
                body = out
            } else {
                body = core
                rejected = 1
            }
        }

        let output = leading + body + trailing + remainder
        return AssistantResult(actionID: actionID, original: text, output: output, rejectedChunks: rejected,
                               segments: TextDiff.diff(text, output), stats: stats)
    }

    // Match a simple subject–verb–pas clause to detect a newly added formal negation.
    private static let frenchNegation = try! NSRegularExpression(
        pattern: #"\A(je|tu|il|elle|on|nous|vous|ils|elles)([ \t]+)(ne[ \t]+|n['’])?\p{L}+[ \t]+pas\b"#,
        options: .caseInsensitive
    )

    private static func preserveFrenchRegister(of source: String, in output: String) -> String {
        guard let original = frenchNegation.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              let edit = frenchNegation.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let subject = Range(original.range(at: 1), in: source),
              let editedSubject = Range(edit.range(at: 1), in: output),
              source[subject].lowercased() == output[editedSubject].lowercased() else { return output }
        if original.range(at: 3).location == NSNotFound, let addedNe = Range(edit.range(at: 3), in: output) {
            // Removing an elided negation can require changing the subject or guessing the intended verb.
            guard output[addedNe].last?.isWhitespace == true else { return source }
            return String(source[subject] + output[editedSubject.upperBound..<addedNe.lowerBound] + output[addedNe.upperBound...])
        }
        return String(source[subject] + output[editedSubject.upperBound...])
    }

    private func generate(actionID: String, text: String, budgetFactor: Double, extra: Int,
                          onPartial: @escaping @Sendable (String) -> Void) async throws -> (String, GenerationStats) {
        let format = generator.format
        let prompt = try generator.renderPrompt(library: library, actionID: actionID, text: text)
        let maxTokens = Int(Double(generator.tokenCount(text)) * budgetFactor) + extra
        let library = self.library
        let result = try await generator.generate(prompt, maxTokens: maxTokens) { partial in
            onPartial(library.clean(partial, format: format))
        }
        return (library.clean(result.text, format: format), result.stats)
    }
}
