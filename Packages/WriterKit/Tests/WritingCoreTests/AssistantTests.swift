import XCTest
@testable import WritingCore

/// Scripted generator: maps the user's text (inside the prompt) to a canned answer.
final class ScriptedGenerator: TextGenerator, @unchecked Sendable {
    let format = "chatml"
    var answers: [String: String]
    private(set) var prompts: [RenderedPrompt] = []

    init(_ answers: [String: String]) { self.answers = answers }

    func generate(_ prompt: RenderedPrompt, maxTokens: Int, onPartial: (@Sendable (String) -> Void)?) async throws -> GenerationOutput {
        prompts.append(prompt)
        let text = answers.first { prompt.suffix.contains("<text>\($0.key)</text>") || prompt.suffix.contains("\($0.key)<|im_end|>") }?.value ?? "?"
        onPartial?(String(text.prefix(text.count / 2)))
        var stats = GenerationStats()
        stats.generatedTokens = text.count / 4
        return GenerationOutput(text: text + "<|im_end|>", stats: stats)
    }
}

final class AssistantTests: XCTestCase {
    func testFixChunksPreserveLayoutAndRejectAnswers() async throws {
        let generator = ScriptedGenerator([
            "i dont know what to do.": "I don't know what to do.",
            "can you explain me how it works?": "Sure, I'd be happy to explain how it works!",
        ])
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        assistant.fixChunkCharacters = 10
        let input = "  i dont know what to do.\n\ncan you explain me how it works? "
        let result = try await assistant.run(actionID: "fix", text: input)
        XCTAssertEqual(result.output, "  I don't know what to do.\n\ncan you explain me how it works? ")
        XCTAssertEqual(result.rejectedChunks, 1)
        XCTAssertTrue(result.hasChanges)
        XCTAssertEqual(result.changes, ["i → I", "dont → don't"])
        XCTAssertEqual(generator.prompts.count, 2)
    }

    func testRewriteUsesWholeTextAndLenientGuard() async throws {
        let generator = ScriptedGenerator(["gonna be late sry": "I apologize, I will be a little late."])
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        let result = try await assistant.run(actionID: "professional", text: "gonna be late sry")
        XCTAssertEqual(result.output, "I apologize, I will be a little late.")
        XCTAssertEqual(result.rejectedChunks, 0)
    }

    func testFixKeepsTheOriginalEnding() async throws {
        let generator = ScriptedGenerator([
            "Je peut pas venir": "je ne peux pas venir.",
            "Je ne peut pas venir": "Je ne peux pas venir.",
            "Je cai pas écrit francai": "Je n'ai pas écrit en français.",
            "tu peut venir ?!": "tu peux venir?",
            "on se voit demain": "on se voit demain.",
        ])
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        let plain = try await assistant.run(actionID: "fix", text: "Je peut pas venir")
        let formal = try await assistant.run(actionID: "fix", text: "Je ne peut pas venir")
        let ambiguous = try await assistant.run(actionID: "fix", text: "Je cai pas écrit francai")
        let question = try await assistant.run(actionID: "fix", text: "tu peut venir ?!")
        let alreadyCorrect = try await assistant.run(actionID: "fix", text: "on se voit demain")
        XCTAssertEqual(plain.output, "Je peux pas venir")
        XCTAssertEqual(formal.output, "Je ne peux pas venir")
        XCTAssertFalse(ambiguous.hasChanges)
        XCTAssertEqual(question.output, "tu peux venir ?!")
        XCTAssertFalse(alreadyCorrect.hasChanges)
    }

    func testFixPreservesApostrophesInUnchangedWords() async throws {
        let unchanged = "Je te l’annonce, j’ai le temps"
        let mixed = "J’ai dit que c'est comme ca"
        let generator = ScriptedGenerator([
            unchanged: "Je te l'annonce, j'ai le temps",
            mixed: "J'ai dit que c’est comme ça",
            "I dont know": "I don't know",
        ])
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)

        let same = try await assistant.run(actionID: "fix", text: unchanged)
        XCTAssertFalse(same.hasChanges)
        let corrected = try await assistant.run(actionID: "fix", text: mixed)
        XCTAssertEqual(corrected.output, "J’ai dit que c'est comme ça")
        XCTAssertEqual(corrected.changes, ["ca → ça"])
        let missing = try await assistant.run(actionID: "fix", text: "I dont know")
        XCTAssertEqual(missing.output, "I don't know")
    }

    func testEmptyTextDoesNotCallModel() async throws {
        let generator = ScriptedGenerator([:])
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        let result = try await assistant.run(actionID: "fix", text: "   ")
        XCTAssertFalse(result.hasChanges)
        XCTAssertTrue(generator.prompts.isEmpty)
    }

    func testCatalogIsPinnedAndConsistent() throws {
        let catalog = try ModelCatalog.bundled()
        let library = try PromptLibrary.bundled()
        XCTAssertNotNil(catalog.model(id: catalog.defaultModelID))
        XCTAssertEqual(Set(catalog.models.map(\.id)).count, catalog.models.count)
        for model in catalog.models {
            XCTAssertNotNil(library.formats[model.format], "\(model.id) has unknown format")
            XCTAssertEqual(model.sha256.count, 64)
            XCTAssertTrue(model.url.absoluteString.contains("/resolve/"), "\(model.id) must pin a revision")
            XCTAssertFalse(model.url.absoluteString.contains("/resolve/main/"), "\(model.id) must pin a commit, not main")
            XCTAssertTrue(model.url.absoluteString.hasSuffix(model.file))
        }
    }

    func testSettingsDecodeLeniently() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "test.\(UUID().uuidString)"))
        defaults.set(Data(#"{"autocorrectMode":"suggest"}"#.utf8), forKey: "settings.v1")
        let settings = SettingsStore(defaults: defaults).load()
        XCTAssertEqual(settings.autocorrectMode, .suggest)
        XCTAssertTrue(settings.hapticFeedback)
        XCTAssertNil(settings.selectedModelID)
    }

    func testOldSettingsRequireNewSetupWithoutLosingPreferences() throws {
        let old = Data(#"{"hasCompletedOnboarding":true,"hapticFeedback":false}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(settings.setupVersion, 0)
        XCTAssertEqual(settings.setupStep, 0)
        XCTAssertFalse(settings.hapticFeedback)
        XCTAssertNil(settings.keyboardCheckID)
    }

    func testKeyboardCheckRejectsStaleOrWrongModelStatus() throws {
        let status = KeyboardStatus(lastSeen: Date(), hasFullAccess: true,
                                    modelID: "current-model", checkID: "current-check")
        XCTAssertTrue(status.verifies(checkID: "current-check", modelID: "current-model"))
        XCTAssertFalse(status.verifies(checkID: "old-check", modelID: "current-model"))
        XCTAssertFalse(status.verifies(checkID: "current-check", modelID: "other-model"))
        XCTAssertFalse(status.verifies(checkID: "current-check", modelID: nil))
        let old = Data(#"{"lastSeen":0,"hasFullAccess":true,"modelName":"old"}"#.utf8)
        let decoded = try JSONDecoder().decode(KeyboardStatus.self, from: old)
        XCTAssertFalse(decoded.verifies(checkID: "current-check", modelID: "current-model"))
    }

}
