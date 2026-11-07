#if canImport(FoundationModels)
import FoundationModels
import WritingCore

@available(iOS 26.0, macOS 26.0, *)
public enum AppleFix {
    public static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: return nil
        case .unavailable(.deviceNotEligible): return "This iPhone does not support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): return "Turn on Apple Intelligence in iPhone Settings to use it for Fix."
        case .unavailable(.modelNotReady): return "The Apple Intelligence model is not ready yet. Try again when it finishes downloading."
        case .unavailable: return "Apple Intelligence is unavailable. Try again or change the Fix engine in Lokey Settings."
        }
    }

    public static func makeAssistant() throws -> WritingAssistant {
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: AppleFixGenerator(),
                                         preserveCasualWording: true)
        assistant.maxInputCharacters = 2_000
        return assistant
    }
}

@available(iOS 26.0, macOS 26.0, *)
private actor AppleFixGenerator: TextGenerator {
    nonisolated let format = "apple"
    private var prepared: [String: LanguageModelSession] = [:]

    nonisolated func renderPrompt(library: PromptLibrary, actionID: String, text: String) throws -> RenderedPrompt {
        let action = library.resolvedAction(actionID, text: text)
        guard action == "fix" || action == "fix_french", let prompt = library.actions[action] else {
            throw PromptError.unknownAction(action)
        }
        let examples = prompt.examples.map { example in
            let input = prompt.userTemplate.replacingOccurrences(of: "{text}", with: example.input)
            return "Input: \(input)\nOutput: \(example.output)"
        }
        let guidance = action == "fix_french" ? Self.frenchGuidance : Self.englishGuidance
        let instructions = ([prompt.system, guidance] + examples).joined(separator: "\n\n")
        return RenderedPrompt(prefix: instructions,
                              suffix: prompt.userTemplate.replacingOccurrences(of: "{text}", with: text))
    }

    func prewarm(prefix: String) async throws {
        guard AppleFix.unavailableReason == nil, prepared[prefix] == nil else { return }
        let session = LanguageModelSession(model: .default, instructions: prefix)
        session.prewarm()
        prepared[prefix] = session
    }

    func generate(_ prompt: RenderedPrompt, maxTokens: Int,
                  onPartial: (@Sendable (String) -> Void)?) async throws -> GenerationOutput {
        if let reason = AppleFix.unavailableReason { throw GeneratorError.unavailable(reason) }
        // Use a fresh conversation for each text, including when taking a prewarmed session.
        let session = prepared.removeValue(forKey: prompt.prefix)
            ?? LanguageModelSession(model: .default, instructions: prompt.prefix)
        do {
            let response = try await session.respond(
                to: prompt.suffix, options: GenerationOptions(sampling: .greedy, maximumResponseTokens: maxTokens))
            return GenerationOutput(text: response.content, stats: GenerationStats())
        } catch {
            #if compiler(>=6.4)
            if #available(iOS 27.0, macOS 27.0, *), let failure = error as? LanguageModelError {
                switch failure {
                case .guardrailViolation, .refusal: throw GeneratorError.appleFixDeclined
                default: throw error
                }
            }
            #endif
            switch error as? LanguageModelSession.GenerationError {
            case .guardrailViolation?, .refusal?: throw GeneratorError.appleFixDeclined
            default: throw error
            }
        }
    }

    private static let frenchGuidance = """
    Corrige les accords et la conjugaison, y compris le subjonctif après « il faut que ».
    Garde les majuscules et minuscules du début des phrases, les emojis et les retours à la ligne.
    Garde mot pour mot les abréviations et formes familières comme stp, dispo, tkt, bah, t'as et j'suis.
    Si une négation n'a pas de « ne » ou de « n' », n'en ajoute jamais, même après « que ».
    Garde la formulation des questions. N'ajoute ni inversion, ni « est-ce que », ni « -tu ».
    Input: <text>il faut absolument que je vends des cartes</text>
    Output: il faut absolument que je vende des cartes
    Input: <text>désolé mais je peut pas passer ce soir</text>
    Output: désolé mais je peux pas passer ce soir
    Input: <text>tu peut confirmer que t'es dispo stp 🙏</text>
    Output: tu peux confirmer que t'es dispo stp 🙏
    Input: <text>je crois qu'on a pas reçus ton message</text>
    Output: je crois qu'on a pas reçu ton message
    """

    private static let englishGuidance = """
    Keep casual words such as gonna, kinda, and tbh. Keep contractions contracted, including when correcting one.
    Keep the original casing of sentence starts, except the pronoun I and proper names.
    Keep every emoji and line break. Keep abbreviations and slang as written.
    Fix subject-verb agreement even when the surrounding message is casual.
    Input: <text>their gonna be late</text>
    Output: they're gonna be late
    Input: <text>yeah thats kinda weird</text>
    Output: yeah that's kinda weird
    Input: <text>they doesn't wanna come lol</text>
    Output: they don't wanna come lol
    Input: <text>We was gonna call you later</text>
    Output: We were gonna call you later
    """
}
#endif
