import Foundation

/// How a model family lays out a chat. Mirrors `formats` in prompts.json.
public struct ChatFormat: Codable, Sendable, Equatable {
    public var turnStart: String
    public var turnEnd: String
    public var generationPrefix: String
    public var assistantHistoryPrefix: String
    public var stop: [String]
    public var stripTokens: [String]
}

/// Thresholds used by `OutputGuard`. Mirrors `guards` in prompts.json.
public struct GuardConfig: Codable, Sendable, Equatable {
    public var minSimilarity: Double
    public var minLengthRatio: Double
    public var maxLengthRatio: Double
    public var allowNewLines: Bool
    public var minWordRetention: Double
    public var rejectAssistantOpeners: Bool
}

public struct PromptExample: Codable, Sendable, Equatable {
    public var input: String
    public var output: String
}

public struct ActionPrompt: Codable, Sendable, Equatable {
    public var system: String
    public var userTemplate: String
    public var examples: [PromptExample]
    public var guardName: String

    enum CodingKeys: String, CodingKey {
        case system, userTemplate, examples
        case guardName = "guard"
    }
}

/// A prompt split at the point where the user's text begins.
///
/// `prefix` only depends on the action and the model family, so an engine can
/// evaluate it once, snapshot the model state and reuse it for every request.
public struct RenderedPrompt: Sendable, Equatable {
    public var prefix: String
    public var suffix: String
    public var stop: [String]
    public var full: String { prefix + suffix }
}

public enum PromptError: Error, Equatable {
    case missingResource(String)
    case unknownAction(String)
    case unknownFormat(String)
    case unknownGuard(String)
}

/// Prompts, chat templates and guard thresholds, loaded from the bundled prompts.json.
/// The evaluation harness (eval/bench.py) reads the same file, so what we measure is what ships.
public struct PromptLibrary: Codable, Sendable {
    public var version: Int
    public var formats: [String: ChatFormat]
    public var actions: [String: ActionPrompt]
    public var guards: [String: GuardConfig]
    public var assistantOpeners: [String]

    public static func bundled() throws -> PromptLibrary {
        guard let url = Bundle.module.url(forResource: "prompts", withExtension: "json") else {
            throw PromptError.missingResource("prompts.json")
        }
        return try JSONDecoder().decode(PromptLibrary.self, from: Data(contentsOf: url))
    }

    public func guardConfig(for action: String) throws -> GuardConfig {
        guard let prompt = actions[action] else { throw PromptError.unknownAction(action) }
        guard let config = guards[prompt.guardName] else { throw PromptError.unknownGuard(prompt.guardName) }
        return config
    }

    public func render(action: String, text: String, format: String) throws -> RenderedPrompt {
        guard let prompt = actions[action] else { throw PromptError.unknownAction(action) }
        guard let fmt = formats[format] else { throw PromptError.unknownFormat(format) }

        func turn(_ role: String, _ body: String) -> String {
            fmt.turnStart + role + "\n" + body + fmt.turnEnd
        }
        var prefix = turn("system", prompt.system)
        for example in prompt.examples {
            prefix += turn("user", prompt.userTemplate.replacingOccurrences(of: "{text}", with: example.input))
            prefix += turn("assistant", fmt.assistantHistoryPrefix + example.output)
        }
        let user = prompt.userTemplate.replacingOccurrences(of: "{text}", with: text)
        let suffix = turn("user", user) + fmt.turnStart + "assistant\n" + fmt.generationPrefix
        return RenderedPrompt(prefix: prefix, suffix: suffix, stop: fmt.stop)
    }

    /// Removes template artifacts the model may echo back (special tokens, the <text> wrapper).
    /// As in LFM3's chat template, the reply is what follows the last `</think>`: a model that
    /// "thinks" its answer despite the empty think block would otherwise appear twice.
    public func clean(_ output: String, format: String) -> String {
        var text = output
        if let end = text.range(of: "</think>", options: .backwards) {
            text = String(text[end.upperBound...])
        }
        for token in formats[format]?.stripTokens ?? [] {
            text = text.replacingOccurrences(of: token, with: "")
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("<text>") && text.hasSuffix("</text>") {
            text = String(text.dropFirst("<text>".count).dropLast("</text>".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
