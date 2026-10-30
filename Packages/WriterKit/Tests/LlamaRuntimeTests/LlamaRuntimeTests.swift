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
        XCTAssertTrue(result.output.hasPrefix("I don't know what to do"), result.output)
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
        let result = try await assistant.run(actionID: "fix", text: "she have two brothers")
        print("METRIC first_fix_after_prewarm_s=\(result.stats.totalSeconds) cached_tokens=\(result.stats.cachedTokens)")
        XCTAssertGreaterThan(result.stats.cachedTokens, 0)
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

    /// Measures what the keyboard extension would pay in footprint to run the model.
    func testKeyboardMemoryFootprint() async throws {
        let path = try modelPath()
        let before = MemoryBudget.footprintBytes() ?? 0
        var config = LlamaGenerator.Configuration.keyboard
        if let v = env["LOKEY_CTX"].flatMap(Int.init) { config.contextLength = v }
        if let v = env["LOKEY_BATCH"].flatMap(Int.init) { config.batchSize = v }
        if let v = env["LOKEY_UBATCH"].flatMap(Int.init) { config.microBatchSize = v }
        let generator = try LlamaGenerator(modelPath: path, format: format, configuration: config)
        let assistant = WritingAssistant(library: try PromptLibrary.bundled(), generator: generator)
        _ = try await assistant.run(actionID: "fix", text: String(repeating: "i dont think their coming tomorow because its raining. ", count: 4))
        let after = MemoryBudget.footprintBytes() ?? 0
        let deltaMB = Double(after &- before) / 1_048_576
        let size = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.doubleValue ?? 0
        let peak = MemoryBudget.peakFootprintBytes().map { Double($0) / 1_048_576 } ?? -1
        print(String(format: "METRIC keyboard_footprint_delta_mb=%.1f before_mb=%.1f after_mb=%.1f peak_mb=%.1f model_file_mb=%.1f",
                     deltaMB, Double(before) / 1_048_576, Double(after) / 1_048_576, peak, size / 1_048_576))
        // Weights are memory-mapped: the footprint must not grow with the model file.
        XCTAssertLessThan(deltaMB, 120)
    }

    /// Prefill/decode throughput for the keyboard and app profiles on this machine.
    func testThroughputProfiles() async throws {
        let path = try modelPath()
        let library = try PromptLibrary.bundled()
        let text = "i dont think their coming tomorow because its raining and the roads is closed"
        var keyboardUbatch128 = LlamaGenerator.Configuration.keyboard
        keyboardUbatch128.microBatchSize = 128
        keyboardUbatch128.batchSize = 128
        let profiles: [(String, LlamaGenerator.Configuration)] = [
            ("keyboard", .keyboard), ("keyboard_ubatch128", keyboardUbatch128), ("app", .app),
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
            let ok = c.accept.map { norm($0) }.contains { $0 == shown || $0.trimmingCharacters(in: ["."]) == shown.trimmingCharacters(in: ["."]) }
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
