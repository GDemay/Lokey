import Foundation

public struct GenerationStats: Equatable, Sendable {
    public var promptTokens = 0
    /// Prompt tokens restored from a cached state instead of being evaluated.
    public var cachedTokens = 0
    public var generatedTokens = 0
    public var prefillSeconds = 0.0
    public var decodeSeconds = 0.0

    public init() {}

    public var totalSeconds: Double { prefillSeconds + decodeSeconds }

    public static func + (lhs: GenerationStats, rhs: GenerationStats) -> GenerationStats {
        var s = GenerationStats()
        s.promptTokens = lhs.promptTokens + rhs.promptTokens
        s.cachedTokens = lhs.cachedTokens + rhs.cachedTokens
        s.generatedTokens = lhs.generatedTokens + rhs.generatedTokens
        s.prefillSeconds = lhs.prefillSeconds + rhs.prefillSeconds
        s.decodeSeconds = lhs.decodeSeconds + rhs.decodeSeconds
        return s
    }
}

public struct GenerationOutput: Sendable {
    public var text: String
    public var stats: GenerationStats

    public init(text: String, stats: GenerationStats) {
        self.text = text
        self.stats = stats
    }
}

public enum GeneratorError: Error, Equatable, LocalizedError {
    case modelNotFound(String)
    case loadFailed(String)
    case contextFailed
    case tokenizationFailed
    case decodeFailed(Int32)
    case promptTooLong(Int, limit: Int)
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let path): return "Model file not found at \(path)."
        case .loadFailed(let path): return "Could not load the model at \(path)."
        case .contextFailed: return "Could not create an inference context (not enough memory?)."
        case .tokenizationFailed: return "Could not tokenize the text."
        case .decodeFailed(let code): return "Inference failed (code \(code))."
        case .promptTooLong(let n, let limit): return "The text is too long (\(n) tokens, limit \(limit))."
        case .unavailable(let reason): return reason
        }
    }
}

/// A local text generator (llama.cpp, Apple's system model, or a test double).
public protocol TextGenerator: AnyObject, Sendable {
    /// Key into `PromptLibrary.formats`.
    var format: String { get }
    /// Generates greedily until a stop string, end of generation, or `maxTokens`.
    /// `onPartial` receives the text generated so far.
    func generate(_ prompt: RenderedPrompt, maxTokens: Int,
                  onPartial: (@Sendable (String) -> Void)?) async throws -> GenerationOutput
    /// Approximate token count for budgeting `maxTokens`.
    func tokenCount(_ text: String) -> Int
    /// Evaluates and caches a prompt prefix ahead of time (e.g. when the keyboard appears).
    func prewarm(prefix: String) async throws
}

public extension TextGenerator {
    func prewarm(prefix: String) async throws {}
    func tokenCount(_ text: String) -> Int { max(1, text.utf8.count / 3) }
}
