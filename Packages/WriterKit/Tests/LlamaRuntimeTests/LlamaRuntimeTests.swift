import XCTest
import WritingCore
@testable import LlamaRuntime

/// Integration tests against a real GGUF model. Set LOKEY_TEST_MODEL=/path/model.gguf
/// (and LOKEY_TEST_FORMAT=lfm3 for LFM3 models) to run them; they are skipped otherwise.
final class LlamaRuntimeTests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var format: String { env["LOKEY_TEST_FORMAT"] ?? "chatml" }

    private func modelPath() throws -> String {
        guard let path = env["LOKEY_TEST_MODEL"], !path.isEmpty else {
            throw XCTSkip("LOKEY_TEST_MODEL not set")
        }
        return path
    }

    func testDecodeValidPrefixNeverSplitsCharacters() {
        let bytes = Array("Café 🙂".utf8)
        XCTAssertEqual(LlamaGenerator.decodeValidPrefix(bytes), "Café 🙂")
        XCTAssertEqual(LlamaGenerator.decodeValidPrefix(Array(bytes.dropLast(1))), "Café ")
        XCTAssertEqual(LlamaGenerator.decodeValidPrefix(Array(bytes.prefix(4))), "Caf")
        XCTAssertEqual(LlamaGenerator.truncateAtStop("Hi<|im_end|>junk", ["<|im_end|>"]), "Hi")
        XCTAssertNil(LlamaGenerator.truncateAtStop("Hi", ["<|im_end|>"]))
    }

    func testFixesASentence() async throws {
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        let result = try await assistant.run(actionID: "fix", text: "i dont know what to do")
        print("METRIC fix_output=\(result.output.debugDescription) seconds=\(result.stats.totalSeconds)")
        XCTAssertEqual(result.output, "I don't know what to do")
    }

    func testFixesMissingApostropheInCasualMessage() async throws {
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        let result = try await assistant.run(actionID: "fix", text: "i dont know how to write it anymore but you got it")
        XCTAssertEqual(result.output, "I don't know how to write it anymore but you got it")
        XCTAssertEqual(result.rejectedChunks, 0)
    }

    func testTranslatesFrenchMessagesIntoEnglish() async throws {
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        for (input, expected) in [
            ("Tu peut venir demain", [["come", "tomorrow"]]),
            ("Je suis dans le train. J'arrive dans dix minutes.", [["train", "ten minutes"], ["train", "10 minutes"]]),
            ("De rien, à demain !", [["welcome", "tomorrow"], ["that's okay", "tomorrow"]]),
        ] {
            let result = try await assistant.run(actionID: "to_english", text: input)
            let output = result.output.lowercased().replacingOccurrences(of: "’", with: "'")
            XCTAssertEqual(result.rejectedChunks, 0, input)
            XCTAssertTrue(expected.contains { $0.allSatisfy { output.contains($0) } }, result.output)
        }
    }

    func testFixesShortSubjectVerbAndPluralErrors() async throws {
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let library = try PromptLibrary.bundled()
        let input = "I has 2 kid"
        let prompt = try library.render(action: "fix", text: input, format: format)
        let generated = try await generator.generate(prompt, maxTokens: 48, onPartial: nil)
        let output = library.clean(generated.text, format: format)
        let verdict = try OutputGuard(library: library, action: "fix", text: input).evaluate(source: input, output: output)
        print("METRIC short_grammar_output=\(output.debugDescription) verdict=\(verdict)")
        XCTAssertTrue(["I have 2 kids.", "I have two kids.", "I have 2 kids", "I have two kids"].contains(output), output)
        let assistant = WritingAssistant(library: library, generator: generator)
        let result = try await assistant.run(actionID: "fix", text: input)
        XCTAssertEqual(result.output, TextChunker.preserveEnding(of: input, in: output))
        XCTAssertEqual(result.rejectedChunks, 0)
    }


    func testFrenchCorrections() async throws {
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let library = try PromptLibrary.bundled()
        let assistant = WritingAssistant(library: library, generator: generator)
        let cases = [
            ("il a oublier les cle a la maison", ["il a oublié les clés à la maison"]),
            ("tu peut venir demain", ["tu peux venir demain"]),
            ("je suis aller au marcher hier", ["je suis allé au marché hier"]),
            ("On se voit à 18 h, comme prévu.", ["On se voit à 18 h, comme prévu.", "On se voit à 18h, comme prévu."]),
            ("Je n'ai pas écrit en français.", ["Je n'ai pas écrit en français."]),
            ("je peut pas venir demain", ["je peux pas venir demain"]),
            ("bah je pense que ça va pas le faire", ["bah je pense que ça va pas le faire"]),
            ("on s'est tromper de train", ["on s'est trompé de train"]),
        ]
        for (input, expected) in cases {
            let result = try await assistant.run(actionID: "fix", text: input)
            let output = result.output.replacingOccurrences(of: "’", with: "'").lowercased()
            print("METRIC french input=\(input.debugDescription) output=\(result.output.debugDescription) seconds=\(result.stats.totalSeconds)")
            XCTAssertTrue(expected.map { $0.lowercased() }.contains(output), result.output)
            XCTAssertEqual(result.rejectedChunks, 0, input)
        }
    }

    func testPrefixSnapshotIsReusedAndDeterministic() async throws {
        let library = try PromptLibrary.bundled()
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let prompt = try library.render(action: "fix", text: "Their going to the park later.", format: format)

        let cold = try await generator.generate(prompt, maxTokens: 32, onPartial: nil)
        let warm = try await generator.generate(prompt, maxTokens: 32, onPartial: nil)
        print("METRIC prefill_cold_s=\(cold.stats.prefillSeconds) prefill_warm_s=\(warm.stats.prefillSeconds) prompt_tokens=\(cold.stats.promptTokens) cached_tokens=\(warm.stats.cachedTokens)")
        XCTAssertEqual(cold.text, warm.text, "restored state must give identical greedy output")
        XCTAssertEqual(cold.stats.cachedTokens, 0)
        XCTAssertGreaterThan(warm.stats.cachedTokens, 0)
        XCTAssertLessThan(warm.stats.prefillSeconds, cold.stats.prefillSeconds)

        // A different action in between must not leak state into the next request.
        _ = try await generator.generate(try library.render(action: "professional", text: "hey whats up", format: format), maxTokens: 24, onPartial: nil)
        let again = try await generator.generate(prompt, maxTokens: 32, onPartial: nil)
        XCTAssertEqual(again.text, cold.text)
    }

    /// The keyboard prewarms the fix prompt when it appears, so the first Fix must not evaluate it again.
    func testPrewarmMakesTheFirstRequestWarm() async throws {
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        await assistant.prewarm()
        // Prewarming runs on one core (the keyboard is drawing meanwhile); requests get all of them back.
        let config = LlamaGenerator.Configuration.keyboard
        XCTAssertEqual(config.prewarmThreads, 1)
        XCTAssertEqual(generator.activeThreads.0, config.threads)
        XCTAssertEqual(generator.activeThreads.1, config.batchThreads)
        let result = try await assistant.run(actionID: "fix", text: "she have two brothers")
        print("METRIC first_fix_after_prewarm_s=\(result.stats.totalSeconds) cached_tokens=\(result.stats.cachedTokens)")
        XCTAssertGreaterThan(result.stats.cachedTokens, 0)
    }


    func testPrewarmMakesFrenchRequestWarm() async throws {
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        await assistant.prewarm(actionID: "fix_french")
        let result = try await assistant.run(actionID: "fix", text: "Je cai pas écrit francai")
        XCTAssertGreaterThan(result.stats.cachedTokens, 0)
        XCTAssertEqual(result.rejectedChunks, 0)
        XCTAssertTrue(result.output.contains("écrire"), result.output)
    }

    func testCancellationStopsGeneration() async throws {
        let library = try PromptLibrary.bundled()
        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let prompt = try library.render(action: "ask", text: "write a long story about the sea", format: format)
        let task = Task { try await generator.generate(prompt, maxTokens: 400, onPartial: nil) }
        try await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
        }
    }

    /// Measures what the keyboard extension would pay in footprint to run the model, stage by stage:
    /// model + context, prompt prewarm (state snapshot), then a request.
    func testKeyboardMemoryFootprint() async throws {
        let path = try modelPath()
        func mb() -> Double { Double(MemoryBudget.footprintBytes() ?? 0) / 1_048_576 }
        let before = mb()
        var config = LlamaGenerator.Configuration.keyboard
        if let v = env["LOKEY_CTX"].flatMap(Int.init) { config.contextLength = v }
        if let v = env["LOKEY_BATCH"].flatMap(Int.init) { config.batchSize = v }
        if let v = env["LOKEY_UBATCH"].flatMap(Int.init) { config.microBatchSize = v }
        if let v = env["LOKEY_KV_Q8"] { config.quantizedKVCache = v == "1" }
        let generator = try LlamaGenerator(modelPath: path, format: format, configuration: config)
        let loaded = mb()
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        await assistant.prewarm()
        let prewarmed = mb()
        _ = try await assistant.run(actionID: "fix", text: String(repeating: "i dont think their coming tomorow because its raining. ", count: 4))
        let after = mb()
        let deltaMB = after - before
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.doubleValue ?? 0
        let peak = MemoryBudget.peakFootprintBytes().map { Double($0) / 1_048_576 } ?? -1
        print(String(format: "METRIC keyboard_footprint_delta_mb=%.1f before_mb=%.1f after_mb=%.1f peak_mb=%.1f model_file_mb=%.1f",
                     deltaMB, before, after, peak, size / 1_048_576))
        // How much of it is freed heap the allocator still holds (would a pressure relief help?).
        MemoryBudget.releaseFreeMemory()
        print(String(format: "METRIC keyboard_footprint_stages load_mb=+%.1f prewarm_mb=+%.1f request_mb=+%.1f released_mb=-%.1f ctx=%d ubatch=%d kv_q8=%d",
                     loaded - before, prewarmed - loaded, after - prewarmed, after - mb(), config.contextLength,
                     config.microBatchSize, config.quantizedKVCache ? 1 : 0))
        // Weights are memory-mapped: the footprint must not grow with the model file.
        XCTAssertLessThan(deltaMB, 120)
    }

    /// Prefill/decode throughput for the keyboard and app profiles on this machine.
    func testThroughputProfiles() async throws {
        let path = try modelPath()
        let library = try PromptLibrary.bundled()
        let text = "i dont think their coming tomorow because its raining and the roads is closed"
        var keyboardUbatch32F16 = LlamaGenerator.Configuration.keyboard
        keyboardUbatch32F16.microBatchSize = 32
        keyboardUbatch32F16.quantizedKVCache = false
        let profiles: [(String, LlamaGenerator.Configuration)] = [
            ("keyboard", .keyboard), ("keyboard_ubatch32_f16kv", keyboardUbatch32F16), ("app", .app),
        ]
        for (name, config) in profiles {
            let generator = try LlamaGenerator(modelPath: path, format: format, configuration: config)
            let prompt = try library.render(action: "fix", text: text, format: format)
            let cold = try await generator.generate(prompt, maxTokens: 48, onPartial: nil)
            let warm = try await generator.generate(prompt, maxTokens: 48, onPartial: nil)
            let prefillTokPerSec = Double(cold.stats.promptTokens) / max(1e-6, cold.stats.prefillSeconds)
            let decodeTokPerSec = Double(warm.stats.generatedTokens) / max(1e-6, warm.stats.decodeSeconds)
            print(String(format: "METRIC profile=%@ threads=%d prefill_tok_s=%.1f decode_tok_s=%.1f warm_total_s=%.3f",
                         name, config.threads, prefillTokPerSec, decodeTokPerSec, warm.stats.totalSeconds))
        }
    }

    /// Runs eval/keyboard_cases.jsonl through the exact app pipeline (prompt, engine, guard).
    /// Set LOKEY_EVAL_CASES to the jsonl path; LOKEY_EVAL_OUT to write a JSON report.
    func testEvalCases() async throws {
        guard let casesPath = env["LOKEY_EVAL_CASES"] else { throw XCTSkip("LOKEY_EVAL_CASES not set") }
        struct Case: Decodable { let id, cat, input: String; let accept: [String] }
        let cases = try String(contentsOfFile: casesPath, encoding: .utf8)
            .split(separator: "\n").map { try JSONDecoder().decode(Case.self, from: Data($0.utf8)) }

        let generator = try LlamaGenerator(modelPath: try modelPath(), format: format, configuration: .keyboard)
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        await assistant.prewarm()

        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: "\u{2019}", with: "'").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        var correct = 0, harmful = 0
        var latencies: [Double] = []
        var rows: [[String: String]] = []
        for c in cases {
            let start = Date()
            let result = try await assistant.run(actionID: "fix", text: c.input)
            latencies.append(Date().timeIntervalSince(start))
            let shown = norm(result.output)
            let ok = c.accept.map { norm(TextChunker.preserveEnding(of: c.input, in: $0)) }.contains(shown)
            if ok { correct += 1 }
            if !ok && shown != norm(c.input) && Similarity.ratio(shown, norm(c.input)) < 0.75 { harmful += 1 }
            rows.append(["id": c.id, "input": c.input, "output": result.output, "ok": ok ? "1" : "0"])
        }
        latencies.sort()
        let summary: [String: Any] = [
            "model": URL(fileURLWithPath: try modelPath()).lastPathComponent,
            "n": cases.count,
            "accuracy": Double(correct) / Double(cases.count),
            "harmful": harmful,
            "mean_ms": latencies.reduce(0, +) / Double(latencies.count) * 1000,
            "p90_ms": latencies[Int(Double(latencies.count) * 0.9) - 1] * 1000,
        ]
        print("METRIC eval=\(summary)")
        if let out = env["LOKEY_EVAL_OUT"] {
            let data = try JSONSerialization.data(withJSONObject: ["summary": summary, "rows": rows], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: out))
        }
        XCTAssertEqual(harmful, 0, "the guard must never let an unrelated rewrite through")
    }
}
