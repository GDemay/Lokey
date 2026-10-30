import Foundation
import WritingCore
import llama

/// llama.cpp-backed `TextGenerator` for GGUF models (LFM2.5, LFM3, ...).
///
/// The fixed part of each prompt (system prompt + few-shot examples) is evaluated once,
/// its sequence state is snapshotted with `llama_state_seq_get_data`, and later requests
/// restore it instead of re-evaluating it. This also works for LFM's hybrid
/// (convolution + attention) memory, which cannot be partially rolled back.
public final class LlamaGenerator: TextGenerator, @unchecked Sendable {
    public struct Configuration: Sendable, Equatable {
        public var contextLength: Int
        public var batchSize: Int
        public var microBatchSize: Int
        /// Decode threads. iPhones have 2 performance cores; ggml ends every op with a barrier, so a
        /// thread on an efficiency core stalls the whole step.
        public var threads: Int
        /// Threads for prompt batches (prefill), which parallelize better.
        public var batchThreads: Int
        public var gpuLayers: Int
        /// llama.cpp can repack weights into faster layouts, but that copies them into
        /// anonymous memory. Keep it off where memory is tight (keyboard extension).
        public var repackWeights: Bool
        public var maxCachedPrefixes: Int
        /// false = register no Metal device in this process (no MTLDevice, no shader compile).
        /// Only effective if this is the process's first llama.cpp use.
        public var allowsMetal: Bool

        public init(contextLength: Int = 2048, batchSize: Int = 512, microBatchSize: Int = 512,
                    threads: Int = Configuration.defaultThreads,
                    batchThreads: Int = Configuration.defaultBatchThreads, gpuLayers: Int = 0,
                    repackWeights: Bool = true, maxCachedPrefixes: Int = 6, allowsMetal: Bool = true) {
            self.contextLength = contextLength
            self.batchSize = batchSize
            self.microBatchSize = microBatchSize
            self.threads = threads
            self.batchThreads = batchThreads
            self.gpuLayers = gpuLayers
            self.repackWeights = repackWeights
            self.maxCachedPrefixes = maxCachedPrefixes
            self.allowsMetal = allowsMetal
        }

        public static var defaultThreads: Int {
            #if os(iOS) && !targetEnvironment(simulator)
            return 2
            #else
            let cores = ProcessInfo.processInfo.activeProcessorCount
            return min(4, max(2, cores / 2 + 1))
            #endif
        }

        public static var defaultBatchThreads: Int {
            let cores = ProcessInfo.processInfo.activeProcessorCount
            #if os(iOS) && !targetEnvironment(simulator)
            return min(4, max(2, cores - 2))
            #else
            return min(4, max(2, cores / 2 + 1))
            #endif
        }

        /// Fits the keyboard extension's memory limit: weights stay memory-mapped
        /// (clean pages, not counted), small context and compute buffers, CPU only.
        /// Measured anonymous footprint for LFM2.5-1.2B: ~42 MB, vs ~89 MB with `.app`
        /// (testKeyboardMemoryFootprint; the micro-batch size dominates).
        public static var keyboard: Configuration {
            Configuration(contextLength: 1024, batchSize: 128, microBatchSize: 32,
                          gpuLayers: 0, repackWeights: false, maxCachedPrefixes: 2, allowsMetal: false)
        }

        /// The containing app has gigabytes of headroom, so it can afford llama.cpp's weight repacking
        /// (an anonymous copy of the weights, forbidden in the keyboard). With the DotProd build this is
        /// the fastest path: 0.34 s vs 0.59 s per fix in the iOS Simulator, 281 vs 107 tok/s prefill
        /// (testThroughputProfiles). Without DotProd it was 5-10x slower, so keep the two together.
        public static var app: Configuration {
            Configuration(contextLength: 2048, batchSize: 512, microBatchSize: 512,
                          repackWeights: true, maxCachedPrefixes: 6)
        }
    }

    public let format: String
    public let modelPath: String
    public let configuration: Configuration

    private let queue = DispatchQueue(label: "llama.generator", qos: .userInitiated)
    private let model: OpaquePointer
    private let context: OpaquePointer
    private let vocab: OpaquePointer
    private let sampler: UnsafeMutablePointer<llama_sampler>
    private var prefixCache: [String: CachedPrefix] = [:]
    private var prefixLRU: [String] = []

    private struct CachedPrefix {
        var state: [UInt8]
        var tokenCount: Int
    }

    public init(modelPath: String, format: String, configuration: Configuration = .app) throws {
        LlamaBackend.initialize(metal: configuration.allowsMetal)
        guard FileManager.default.fileExists(atPath: modelPath) else { throw GeneratorError.modelNotFound(modelPath) }
        self.modelPath = modelPath
        self.format = format
        self.configuration = configuration

        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = Int32(configuration.gpuLayers)
        modelParams.use_extra_bufts = configuration.repackWeights
        modelParams.load_mode = LLAMA_LOAD_MODE_MMAP

        // CPU only unless GPU layers were requested: avoids Metal buffers entirely.
        var devices: [ggml_backend_dev_t?] = []
        if configuration.gpuLayers == 0, let cpu = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU) {
            devices = [cpu, nil]
        }
        let loaded: OpaquePointer? = devices.withUnsafeMutableBufferPointer { buffer in
            if !buffer.isEmpty { modelParams.devices = buffer.baseAddress }
            return llama_model_load_from_file(modelPath, modelParams)
        }
        guard let model = loaded else { throw GeneratorError.loadFailed(modelPath) }

        var ctxParams = llama_context_default_params()
        ctxParams.n_ctx = UInt32(configuration.contextLength)
        ctxParams.n_batch = UInt32(configuration.batchSize)
        ctxParams.n_ubatch = UInt32(min(configuration.microBatchSize, configuration.batchSize))
        ctxParams.n_seq_max = 1
        ctxParams.n_threads = Int32(configuration.threads)
        ctxParams.n_threads_batch = Int32(configuration.batchThreads)
        ctxParams.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_AUTO
        ctxParams.no_perf = true
        if configuration.gpuLayers == 0 {
            ctxParams.offload_kqv = false
            ctxParams.op_offload = false
        }
        guard let context = llama_init_from_model(model, ctxParams) else {
            llama_model_free(model)
            throw GeneratorError.contextFailed
        }
        guard let vocab = llama_model_get_vocab(model) else {
            llama_free(context)
            llama_model_free(model)
            throw GeneratorError.loadFailed(modelPath)
        }
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_greedy())

        self.model = model
        self.context = context
        self.vocab = vocab
        self.sampler = chain
    }

    deinit {
        llama_sampler_free(sampler)
        llama_free(context)
        llama_model_free(model)
    }

    // MARK: TextGenerator

    public func tokenCount(_ text: String) -> Int {
        (try? tokenize(text, addSpecial: false).count) ?? max(1, text.utf8.count / 3)
    }

    public func prewarm(prefix: String) async throws {
        try await run { _ in
            _ = try self.loadPrefix(prefix)
        }
    }

    public func generate(_ prompt: RenderedPrompt, maxTokens: Int,
                         onPartial: (@Sendable (String) -> Void)?) async throws -> GenerationOutput {
        try await run { token in
            try self.generateSync(prompt, maxTokens: maxTokens, cancel: token, onPartial: onPartial)
        }
    }

    /// Drops cached prompt states (e.g. on a memory warning).
    public func purgeCaches() {
        queue.sync {
            prefixCache.removeAll()
            prefixLRU.removeAll()
        }
    }

    // MARK: Internals (all on `queue`)

    private func run<T>(_ work: @escaping (CancelToken) throws -> T) async throws -> T {
        let token = CancelToken()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                queue.async {
                    do {
                        try token.check()
                        continuation.resume(returning: try work(token))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            token.cancel()
        }
    }

    /// Restores (or evaluates and caches) the prompt prefix. Returns (prefix tokens, cached?).
    private func loadPrefix(_ prefix: String) throws -> (Int, Bool) {
        let memory = llama_get_memory(context)
        llama_memory_clear(memory, true)
        if let cached = prefixCache[prefix] {
            let restored = cached.state.withUnsafeBufferPointer { buffer in
                llama_state_seq_set_data(context, buffer.baseAddress, buffer.count, 0)
            }
            if restored > 0 {
                touch(prefix)
                return (cached.tokenCount, true)
            }
            llama_memory_clear(memory, true)
            prefixCache[prefix] = nil
        }
        let tokens = try tokenize(prefix, addSpecial: true)
        try ensureFits(tokens.count)
        try decode(tokens, cancel: nil)
        let size = llama_state_seq_get_size(context, 0)
        if size > 0 {
            var state = [UInt8](repeating: 0, count: size)
            let written = state.withUnsafeMutableBufferPointer { buffer in
                llama_state_seq_get_data(context, buffer.baseAddress, size, 0)
            }
            if written == size {
                prefixCache[prefix] = CachedPrefix(state: state, tokenCount: tokens.count)
                touch(prefix)
            }
        }
        return (tokens.count, false)
    }

    private func touch(_ prefix: String) {
        prefixLRU.removeAll { $0 == prefix }
        prefixLRU.append(prefix)
        while prefixLRU.count > max(1, configuration.maxCachedPrefixes) {
            prefixCache[prefixLRU.removeFirst()] = nil
        }
    }

    private func generateSync(_ prompt: RenderedPrompt, maxTokens: Int, cancel: CancelToken,
                              onPartial: (@Sendable (String) -> Void)?) throws -> GenerationOutput {
        var stats = GenerationStats()
        let start = DispatchTime.now()

        let (prefixTokens, cached) = try loadPrefix(prompt.prefix)
        let suffixTokens = try tokenize(prompt.suffix, addSpecial: false)
        try ensureFits(prefixTokens + suffixTokens.count + maxTokens)
        try decode(suffixTokens, cancel: cancel)

        stats.promptTokens = prefixTokens + suffixTokens.count
        stats.cachedTokens = cached ? prefixTokens : 0
        let prefillEnd = DispatchTime.now()
        stats.prefillSeconds = seconds(from: start, to: prefillEnd)

        llama_sampler_reset(sampler)
        var bytes: [UInt8] = []
        var generated = 0
        while generated < maxTokens {
            try cancel.check()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            bytes.append(contentsOf: piece(token))
            generated += 1
            let partial = Self.decodeValidPrefix(bytes)
            if Self.truncateAtStop(partial, prompt.stop) != nil { break }
            onPartial?(partial)
            let rc = llama_decode(context, llama_batch_get_one(&token, 1))
            if rc != 0 { throw GeneratorError.decodeFailed(rc) }
        }
        let decoded = String(decoding: bytes, as: UTF8.self)
        let text = Self.truncateAtStop(decoded, prompt.stop) ?? decoded
        stats.generatedTokens = generated
        stats.decodeSeconds = seconds(from: prefillEnd, to: DispatchTime.now())
        return GenerationOutput(text: text, stats: stats)
    }

    private func ensureFits(_ tokens: Int) throws {
        let limit = Int(llama_n_ctx(context))
        if tokens > limit { throw GeneratorError.promptTooLong(tokens, limit: limit) }
    }

    private func decode(_ tokens: [llama_token], cancel: CancelToken?) throws {
        var start = 0
        while start < tokens.count {
            try cancel?.check()
            let end = min(start + configuration.batchSize, tokens.count)
            var slice = Array(tokens[start..<end])
            let rc = slice.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
            if rc != 0 { throw GeneratorError.decodeFailed(rc) }
            start = end
        }
    }

    private func tokenize(_ text: String, addSpecial: Bool) throws -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 8)
        var n = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), addSpecial, true)
        if n < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-n))
            n = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), addSpecial, true)
        }
        guard n >= 0 else { throw GeneratorError.tokenizationFailed }
        return Array(tokens.prefix(Int(n)))
    }

    private func piece(_ token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 32)
        var n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        if n < 0 {
            buffer = [CChar](repeating: 0, count: Int(-n))
            n = llama_token_to_piece(vocab, token, &buffer, Int32(buffer.count), 0, false)
        }
        return buffer.prefix(Int(max(0, n))).map { UInt8(bitPattern: $0) }
    }

    /// The text before the earliest stop string, or nil if none occurs.
    static func truncateAtStop(_ text: String, _ stops: [String]) -> String? {
        let first = stops.compactMap { text.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        return first.map { String(text[..<$0.lowerBound]) }
    }

    /// Decodes the longest prefix that does not end inside a multi-byte UTF-8 sequence.
    static func decodeValidPrefix(_ bytes: [UInt8]) -> String {
        var end = bytes.count
        var back = 0
        while back < min(4, bytes.count) {
            let byte = bytes[bytes.count - 1 - back]
            if byte & 0b1100_0000 != 0b1000_0000 {
                let needed = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : byte >= 0xC0 ? 2 : 1
                if needed > back + 1 { end = bytes.count - 1 - back }
                break
            }
            back += 1
        }
        return String(decoding: bytes[..<end], as: UTF8.self)
    }

    private func seconds(from a: DispatchTime, to b: DispatchTime) -> Double {
        Double(b.uptimeNanoseconds - a.uptimeNanoseconds) / 1e9
    }
}

/// Cooperative cancellation shared between a Swift task and the inference queue.
final class CancelToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
}

enum LlamaBackend {
    private static let once: Void = {
        llama_backend_init()
        if ProcessInfo.processInfo.environment["LLAMA_VERBOSE"] == nil {
            llama_log_set({ _, _, _ in }, nil)
        }
    }()

    /// ggml creates the Metal device and compiles its embedded shader library when the backend
    /// registry is first built, so the CPU-only opt-out must come before llama_backend_init.
    static func initialize(metal: Bool = true) {
        if !metal { setenv("GGML_METAL_DEVICES", "0", 1) }
        _ = once
    }
}
