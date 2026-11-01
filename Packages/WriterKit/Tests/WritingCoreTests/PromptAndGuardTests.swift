import XCTest
@testable import WritingCore

final class PromptAndGuardTests: XCTestCase {
    struct Golden: Decodable {
        struct Render: Decodable { let action, format, text, full: String }
        struct GuardCase: Decodable {
            let source, output: String
            let accepted: Bool
            let reason: String
            let similarity, retention: Double
        }
        let renders: [Render]
        let guards: [GuardCase]
    }

    var library: PromptLibrary!
    var golden: Golden!

    override func setUpWithError() throws {
        library = try PromptLibrary.bundled()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "python_golden", withExtension: "json", subdirectory: "Fixtures"))
        golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    func testEveryActionHasAPromptAndGuard() throws {
        for action in WritingAction.all {
            XCTAssertNotNil(library.actions[action.id], "missing prompt for \(action.id)")
            XCTAssertNoThrow(try library.guardConfig(for: action.id))
        }
    }

    /// The Swift renderer must produce byte-identical prompts to eval/bench.py,
    /// otherwise benchmark numbers would not describe the app.
    func testRenderMatchesPythonHarness() throws {
        XCTAssertFalse(golden.renders.isEmpty)
        for r in golden.renders {
            let prompt = try library.render(action: r.action, text: r.text, format: r.format)
            XCTAssertEqual(prompt.full, r.full, "\(r.action)/\(r.format)/\(r.text)")
        }
    }

    func testPrefixDoesNotDependOnText() throws {
        let a = try library.render(action: "fix", text: "one", format: "chatml")
        let b = try library.render(action: "fix", text: "two words", format: "chatml")
        XCTAssertEqual(a.prefix, b.prefix)
        XCTAssertTrue(a.suffix.contains("<text>one</text>"))
        XCTAssertTrue(a.suffix.hasSuffix("<|im_start|>assistant\n"))
    }

    func testLFM3DisablesThinking() throws {
        let prompt = try library.render(action: "fix", text: "x", format: "lfm3")
        XCTAssertTrue(prompt.suffix.hasSuffix("<|im_start|>assistant\n<think></think>"))
        XCTAssertEqual(library.clean("<think></think>Hello.", format: "lfm3"), "Hello.")
        // LFM3 sometimes "thinks" the answer, closes the block, then answers (CI eval, b12015).
        XCTAssertEqual(library.clean("I received it.</think>I received it.", format: "lfm3"), "I received it.")
        XCTAssertEqual(library.clean("<think>fix spelling</think>\n\nI received it.<|im_end|>", format: "lfm3"), "I received it.")
    }

    func testCleanStripsWrapperAndTokens() {
        XCTAssertEqual(library.clean("  <text>Fixed.</text><|im_end|>", format: "chatml"), "Fixed.")
        XCTAssertEqual(library.clean("Fixed.", format: "chatml"), "Fixed.")
    }

    /// Guard decisions must match the Python harness on real model outputs.
    func testGuardMatchesPythonHarness() throws {
        let outputGuard = try OutputGuard(library: library, action: "fix")
        var mismatches: [String] = []
        for g in golden.guards {
            let verdict = outputGuard.evaluate(source: g.source, output: g.output)
            let sim = Similarity.ratio(g.source, g.output)
            let ret = Similarity.wordRetention(source: g.source, output: g.output)
            if verdict.isAccepted != g.accepted || abs(sim - g.similarity) > 1e-4 || abs(ret - g.retention) > 1e-4 {
                mismatches.append("\(g.source) -> \(g.output): swift=\(verdict) sim=\(sim) ret=\(ret); python=\(g.accepted) \(g.reason) sim=\(g.similarity) ret=\(g.retention)")
            }
        }
        XCTAssertTrue(mismatches.isEmpty, mismatches.joined(separator: "\n"))
    }

    func testGuardRejectsAnswersAndKeepsFixes() throws {
        let g = try OutputGuard(library: library, action: "fix")
        XCTAssertEqual(g.evaluate(source: "I want to come to.", output: "I want to come to Café Luna."), .rejected(.leakage))
        XCTAssertEqual(g.evaluate(source: "Can you explain me how it works?", output: "Sure, I'd be happy to explain how it works!"), .rejected(.opener))
        XCTAssertEqual(g.evaluate(source: "tell me a joke", output: "Why did the chicken cross the road?\nTo get to the other side."), .rejected(.length))
        XCTAssertEqual(g.evaluate(source: "Your welcome!", output: "Welcome!"), .rejected(.retention))
        XCTAssertEqual(g.evaluate(source: "Their going to the park later.", output: "They're going to the park later."), .accepted)
        XCTAssertEqual(g.evaluate(source: "I live here since 3 years.", output: "I have lived here for 3 years."), .accepted)
        XCTAssertEqual(g.evaluate(source: "Teh meeting is at 3pm.", output: "The meeting is at 3pm."), .accepted)
    }

    func testRewriteGuardAllowsToneChanges() throws {
        let g = try OutputGuard(library: library, action: "professional")
        XCTAssertEqual(g.evaluate(source: "gonna be late sry", output: "I apologize, I will be arriving a little late."), .accepted)
        XCTAssertEqual(g.evaluate(source: "gonna be late sry", output: "Sure! Here is a professional version: I will be late."), .rejected(.opener))
    }

    func testGuardAcceptsSubjectAgreementWithoutDroppingContentChecks() throws {
        let g = try OutputGuard(library: library, action: "fix")
        for (source, output) in [
            ("I has 2 kid", "I have 2 kids."),
            ("He have a dog.", "He has a dog."),
            ("He do it.", "He does it."),
            ("I were late.", "I was late."),
        ] {
            XCTAssertEqual(g.evaluate(source: source, output: output), .accepted, "\(source) → \(output)")
        }
        XCTAssertEqual(Similarity.wordRetention(source: "I has 2 kid", output: "I have 2 kids."), 1)
        XCTAssertEqual(Similarity.leakedWords(source: "He has a dog.", output: "He does have a dog.",
                                            exampleWords: ["have", "does"]), ["does"])
        XCTAssertEqual(g.evaluate(source: "I have 2 kids.", output: "I had 2 kids."), .rejected(.retention))
        XCTAssertEqual(g.evaluate(source: "I have a cat.", output: "I have a dog."), .rejected(.retention))
        XCTAssertEqual(g.evaluate(source: "I has 2 kid", output: "Kids are great!"), .rejected(.similarity))
    }
}
