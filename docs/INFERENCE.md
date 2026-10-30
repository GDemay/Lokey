> **Status (2026-10-30):** decision taken: keep llama.cpp. Item 1 (DotProd/fp16 arm64-only build,
> BLAS off, iOS 26 minimum) is implemented in `scripts/bootstrap.sh` + `scripts/patch_llama_xcframework.py`,
> with a CI binary audit. Decode threads are 2 on iPhone (item 4, partly). Items 2–3 (input-copy
> speculative decoding, prefill as you type) are the next engineering work; see AGENTS.md §7.
> Numbers below marked [ours] are from this project's CI; everything else is cited.

# Decision memo: which inference runtime Lokey should use

**Date:** 2026-10-30 · **From:** lead engineer · **Question from the founder:** "Is llama.cpp the best today? Is there something newer and more efficient? I want the most efficient stack."

**Inputs:** four research reports (runtimes, Liquid AI, techniques, benchmarks) and a fact-check pass. Where the fact-check refuted or corrected a claim, this memo uses the corrected version.

**Number labels:**
- **[ours]**: we measured it.
- **[ind]**: an independent third party measured it.
- **[vendor]**: the runtime's or the model's maker published it.
- **[src]**: verified by reading source code or disassembling a binary.
- **[est]**: our estimate. It has not been measured.

---

## 1. Verdict

**llama.cpp is not the fastest engine on Apple hardware in 2026. It is the only one that can run inside our keyboard, so it stays.**

On the iPhone GPU, uzu, MLX Swift and LiteRT-LM decode about 3–60% faster than llama.cpp, depending on the model and on who measured. Each of them fails the keyboard on at least one count:
- it copies the weights into memory that counts against the process,
- it runs only on the GPU or ANE,
- it has no LFM3 support, or
- its license is not OSI.

The newer Apple paths (Core AI, and Core ML on the ANE) don't fit in a keyboard's 77 MB either. Since iOS 27, Neural Engine memory counts against the app. Liquid AI has itself deprecated its LEAP SDK and now tells iOS developers to call llama.cpp's xcframework directly.

- **Keyboard extension: keep llama.cpp (CPU-only, memory-mapped QAD Q4_0) and rebuild it.** The fact-check disassembled the iOS slice of the official b12017 xcframework.
  - It contains 0 `sdot` and 0 `smmla` instructions. The macOS slice of the same file has 153 `sdot`.
  - It also turns on an Accelerate BLAS path. That path allocates an anonymous ~64 MiB buffer whenever one of our 32-token `n_ubatch` chunks is full.
  - The efficiency gains come from fixing the build, then adding input-copy speculative decoding and prefill as the user types. A different runtime would not give them.
- **Foreground app: keep llama.cpp and run it on Metal.** It reads the same GGUF file from the App Group, so there is one engine and one ~700 MB download, and no other runtime supports LFM3.
  - uzu (MIT) is the only LFM2.5 engine measured faster on the iPhone GPU: +19% decode. That figure comes from the vendor and does not compare like with like.
  - That gain doesn't justify a second engine and a second weight download for corrections of 30–60 tokens.
- **Hybrid, as an experiment only:** spend one day testing Apple Foundation Models as an optional keyboard backend. Its model runs in a system process and doesn't count against the extension's memory. Nobody has confirmed that a keyboard can reach it.

---

## 2. Candidates compared

| Runtime | License | LFM2.5 / LFM3 | Fits the keyboard? (weight memory; compute) | Apple CPU speed vs llama.cpp | iPhone GPU / ANE speed | Maturity |
|---|---|---|---|---|---|---|
| **llama.cpp** (b12017) | MIT (OSI) | Yes / **Yes** (b11960+, the only runtime with LFM3) | **Yes.** Weights are memory-mapped as clean pages that don't count [src]. One independent test showed 191 MB charged while 2.9 GB of memory-mapped GGUF was resident [ind]. Must run CPU-only with repacking, KleidiAI and BLAS off. | Baseline: 0.49 s per sentence for the 1.2B on a 3-vCPU M1 runner [ours]. The stock iOS slice has no DotProd [src]. | Metal, iPhone 17 Pro Max, LFM2.5-1.2B-Thinking Q4_K_S: 86.5 decode / 1,994 prefill tok/s on an old build (b11669) [vendor-run by Mirai]. Qwen3.5-2B: 38.7 vs MLX 61.2 [ind]. **Every published iPhone llama.cpp number is Metal; none is CPU-only.** | Very high: about 15 tags a day, and Liquid upstreams LFM support itself. |
| **uzu** (Mirai, 0.6.15) | MIT | LFM2.5 230M–2.6B / not verified | **No.** Metal first. The CPU backend is a scalar reference loop with no NEON [src]. The README recommends the Increased Memory entitlement. | Far slower (scalar code) [src] | LFM2.5-1.2B-Thinking: 103.2 decode / 4,666 prefill tok/s at 756 MiB, which is 1.19× / 2.3× llama.cpp. LFM2.5-350M: 289.8 vs 237.3 [vendor]. | Young, single vendor, no independent iPhone run |
| **MLX Swift** (mlx-swift 0.33.0 / mlx-swift-lm) | MIT | Yes / **No** | **No.** Weights are read with `read()` into process memory and never memory-mapped [src]. GPU only. The 1.2B 4-bit file is 663 MB. | Not a target | LFM2.5-1.2B 4-bit: 59.7–70.2 decode tok/s, time to first token 90–244 ms, iPhone 17 Pro [ind blog]. 89.5 / 2,833 tok/s at 1,017 MiB on Pro Max [vendor-run by Mirai]. | High (Apple) |
| **Apple Core AI** (iOS 27) | OS framework. The coreai-models repo is BSD-3; the conversion tools' license is unconfirmed. | Community LFM2.5 port only / No | **No.** iOS 27 counts ANE memory against the process. The model is compiled on the device at first load (77 s for a 1B model on the ANE). Use from a keyboard is unverified. | n/a | LFM2.5-1.2B int8 on GPU about 45 tok/s (beta-era) [ind]. Qwen3-0.6B: ANE 117–122, GPU 193 cold [ind]. | New, iOS 27+ only |
| **Core ML stateful / CoreML-LLM / Anemll** | OS framework + MIT | LFM2.5-350M only (CoreML-LLM) / No | **No.** Measured footprints of 98–256 MB, and ANE memory counts in iOS 27. | n/a | LFM2.5-350M: 52 tok/s on ANE [ind; measured by the CoreML-LLM author]. Qwen3.5-2B: 28 vs llama.cpp Metal 39 [ind]. Best sustained speed (keeps 67%). | Community |
| **Foundation Models** | OS framework with Apple's proprietary ~3B model; our app stays MIT | No LFM. Adapters are dropped in OS 27. | **Maybe.** Apple DTS says the model is not charged to the extension, but "some extensions don't allow XPC", and keyboards are untested. iPhone 15 Pro or later only. | n/a | Mac: 85 tok/s and 0.11 J/token, the lowest energy measured; 27 MB in-process [ind] | Apple, iOS 26+ |
| **ExecuTorch** (v1.5.1) | BSD-3 | LFM2/LFM2.5 example (XNNPACK 8da4w, MLX, coreml_fp32) / No | **No.** XNNPACK repacks weights into its own memory, and the fp32 KV cache is allocated up front (50 MB at 2k context for the 1.2B). | About equal to llama.cpp on Android CPU (Llama-3.2-1B, Galaxy S25 Ultra) [ind paper] | No 2026 iPhone LLM numbers. The MPS backend is deprecated and the MLX delegate is experimental. | Mature core, thin iOS LLM path |
| **ONNX Runtime GenAI** (0.17) | MIT | LFM2 since v0.14 / an LFM3 ONNX export exists (q4 is 1.63 GB) | **Unlikely.** External weights are memory-mapped, but CPU prepacking makes a copy (fix: `disable_prepacking`). No official iOS genai package. | No data | No data | Mature runtime, weak iOS LLM story |
| **LiteRT-LM** (v0.19) | Apache-2.0 | Community conversions with known bugs / No | **No.** LFM2.5-350M peaks at 836–1,274 MB on Android CPU. | iPhone 17 Pro CPU, Gemma 4 E2B: 532 prefill / 25 decode tok/s at 607 MB [vendor] | Fastest GPU result on Gemma 4 E2B: 61.1 tok/s, 0.147 J/tok [ind]. No ANE support. | Swift API is "Early Preview" |
| **MNN** (3.6.2) | Apache-2.0 | lfm2 and lfm2_moe (so LFM2.5) / **No** | Unverified. It has mmap options, but its SME2/KleidiAI kernels likely repack the weights. | No data | No data | Mature (Alibaba) |
| **MLC LLM** | Apache-2.0 | No / No | **No.** GPU only on iOS. | n/a | No 2025–26 iPhone data | Active |
| **Cactus** (v2.2.2) | **Not OSI** (paid license above $2M funding or revenue) | Yes (Liquid partner) | **No.** 644 MB footprint on Gemma 4. | Vendor CPU INT8: LFM2.5-350M on iPhone 13 mini 496 prefill / 88 decode at 56 MB; LFM2.5-1.2B-Thinking on A19 Pro 420 / 64 at 1,128 MB [vendor] | Gemma 4 E2B on Metal: 37 decode [vendor]. The default CQ4 build it ships scored 3% on GSM8K [ind]. | Ruled out by its license |
| **ik_llama.cpp** | MIT | LFM2.5 yes / unknown | Plausible but unverified: it stores pre-repacked Q4_0_R8 weights as GGUF types that can be memory-mapped. | Unknown | Metal not supported | Fork, last synced with upstream in Aug 2024 |

**Not suitable:**
- Nexa SDK runs on a proprietary engine.
- RunAnywhere MetalRT has no confirmed license and no iPhone data. Its vendor figure is 570 tok/s for LFM2.5-1.2B on an M4 Max.

**How to read the numbers:**
- **No neutral CPU-only benchmark across runtimes exists on Apple hardware.** The independent bench app leaves llama.cpp's default `n_gpu_layers=-1` on devices, so its iPhone llama.cpp figures are Metal.
- **Mirai's comparison is not like for like.**
  - It used the Thinking model.
  - llama.cpp ran unsloth's Q4_K_S file while uzu ran Mirai's own checkpoint.
  - The llama.cpp build is from about 350 tags ago.
  - For the 350M, llama.cpp did use Liquid's Q4_0 and still trailed: 237 vs 290 tok/s.
- **On the Apple GPU, llama.cpp's Metal path is the weakest of the modern runtimes [ind]:**
  - It used the most energy: 0.483 J/tok sustained on iPhone 17 Pro with Gemma 4 E2B.
  - On a Mac, MLX decodes about 1.8–2.1× faster on small models, and about 2× faster on hybrid models.
  - llama.cpp still has the best prefill on short prompts: 2,504 vs 702 tok/s on Qwen3.5-2B.
  - Vendor figures on M4 Max: LFM2.5-1.2B runs at 570 (MetalRT), 550 (uzu), 509 (mlx-lm) and 372 tok/s (llama.cpp).
- **For small models, the CPU is not hopeless.** On an iPhone 15 Pro, a 1B F16 model on 2 CPU threads ran at 17 tok/s versus 12.8 tok/s on Metal [ind, 2025]. On an iPhone 17, the GPU is generally 2–5× faster than the CPU (LiteRT: 2.2× decode, 5.4× prefill).

---

## 3. The recommended stack

### 3.1 Target configuration

**Keyboard extension:**
- llama.cpp b12017 or later, built ourselves and linked statically into the extension, with these build flags:
  - `GGML_NATIVE=OFF`, `GGML_CPU_ARM_ARCH=armv8.4-a+dotprod+fp16`
  - `GGML_BLAS=OFF`, `GGML_METAL=OFF`, KleidiAI off
- Runtime parameters: `load_mode=LLAMA_LOAD_MODE_MMAP`, `use_extra_bufts=false`, `n_gpu_layers=0`.
- Model: QAD Q4_0 of LFM2.5-1.2B by default, with the 350M on slow devices if the quality check allows (item 6).
- Threads: 2 for decode, a persistent threadpool, and `.userInitiated` QoS.
- Our own input-copy speculative decoding on the C API, using `n_rs_seq`.
- Prefill as the user types, on top of the prefix snapshots we already save.

**Foreground app:** the same GGUF file, a Metal-enabled build with `n_gpu_layers=99`, and the same speculative loop.

### 3.2 Ranked changes (expected gain per engineering effort)

| # | Change | Expected speedup | Memory impact | Effort | Main risks |
|---|---|---|---|---|---|
| 1 | **Rebuild the iOS slice:** add DotProd and fp16, turn BLAS and Metal off in the extension, set the safe parameters explicitly | [est] decode 1.3–2×; prefill and verify batches 2–4× on iPhone. About 0 on Mac, which already has DotProd. | Removes a hidden +64 MiB anonymous spike (and +512 MiB if 32 or more logit rows are ever requested). **Adds ~660 MB and crashes if `use_extra_bufts` stays true.** | 0.5–1 day | Needs an A13 or newer chip (iOS 26+ minimum); older chips crash on illegal instructions. Mac numbers may shift once BLAS is off. |
| 2 | **Input-copy speculative decoding** (custom, C API) | [est] decode share 1.5–2.5×; end to end about 1.3–1.7× on our M1 numbers; best on sentences with nothing to fix | +~2.5 MiB of state snapshots and +~4.25 MiB of logits at K=16 [est] | 3–5 days | Open PR #29085 (context creation failure); the rollback rule from #31368; experimental API; batched math can break near-ties differently |
| 3 | **Prefill as the user types** | [est] hides most of the 0.16 s prefill, up to about a third of today's latency | About 0 | 2–3 days | Wasted CPU and energy when the user edits; unstable tokenization at word boundaries; typing jank if not debounced |
| 4 | **Threads, QoS, persistent threadpool, warm-up when the keyboard appears** | [est] 0–30% latency, lower energy | 0 | Hours | Placement on efficiency cores; QoS inheritance by worker threads is unconfirmed |
| 5 | **Trim the KV cache / context** (q8_0 KV, or a smaller n_ctx if the prompt fits) | None for speed; it frees memory headroom for items 2–3 | About −6 MiB [est, from config] | Hours | Quantizing V needs flash attention; small quality risk |
| 6 | **Model choice per device** (350M or 230M on A13/A14, or as a "fast mode") | [est] 2.5–3.5× vs the 1.2B | Smaller resident file, less risk of pages being evicted | 1–2 days plus quality evaluation | Quality loss, which must be measured |
| 7 | **i8mm variant with runtime dispatch** (A15+) | [est] more batch and verify gain from `smmla`; size unknown | 0 if repacking stays off | 2–4 days | `GGML_CPU_ALL_VARIANTS` needs `GGML_BACKEND_DL` and shared libraries; untested on iOS and in extensions |
| 8 | **Foundation Models as an optional keyboard backend** | Unknown; 85 tok/s on Mac | The model isn't charged to the extension | 1-day test | The keyboard may block the XPC connection; iPhone 15 Pro+ only; not our model; no adapters; quality unknown |
| 9 | **Foreground app: Metal path, reusing item 2** | [est] larger speculative gains than on CPU, because small verify batches cost almost nothing on a bandwidth-bound GPU | App only | 1–2 days | Liquid's batch-size 8–32 Metal kernels (#27441) are still an unmerged draft |
| 10 | **Pre-repacked weights that can be memory-mapped** (upstream patch or ik_llama.cpp) | [ind, upstream PRs, M4 Max, K-quants] repacking gives prefill 2.3–3.1× and decode 1.15–1.22× | 0 if the weights stay file-backed | Weeks, plus maintaining a fork | Upstream closed the idea as "not planned" (#19578); the ik_llama.cpp fork is stale |

### 3.3 Notes on each item

**1. Rebuild the iOS slice. Do this first; everything else depends on it.**

*Why:*
- `build-xcframework.sh` sets `GGML_NATIVE=OFF`, passes no `GGML_CPU_ARM_ARCH`, and sets `IOS_MIN_OS_VERSION=16.4`. clang therefore defaults to `apple-a7`, which has no DotProd.
- Correction to the reports: raising the minimum to iOS 26 only moves the default to `apple-a12`, which still has no DotProd. The flag has to be set explicitly.
- Without DotProd [src]:
  - `ggml_vdotq_s32` is emulated with `vmull_s8` plus pairwise adds;
  - the tinyBLAS Q4_0 batch path (used for 2 or more tokens) is compiled out;
  - repacking is never selected.
- Our 0.49 s comes from the macOS slice, which defaults to `apple-m1` and has DotProd. So it overstates current iPhone speed.

*Build flags:*
- Set `-DGGML_CPU_ARM_ARCH=armv8.4-a+dotprod+fp16` on the iOS device slice and the arm64 simulator slice.
- This is safe with an iOS 26+ minimum: iOS 26 and 27 start at the A13 / iPhone 11, according to press reports.
- If we support older iOS versions, we need a fallback build without DotProd.

*BLAS off:* the BLAS backend is registered ahead of the CPU backend [src].
- It takes any `MUL_MAT` where ne0, ne1 and ne10 are all at least 32.
- It dequantizes the whole weight matrix into a float32 work buffer that persists and only ever grows.
- For the 2048×8192 feed-forward matrix that is 64 MiB. For the 65,536×2048 output projection it would be 512 MiB, if a batch ever requests 32 or more logit rows.

*Metal off in the extension:* use a separate static build for the extension so no accelerator backend can be picked behind our back. If the extension ever links a Metal-enabled build, set `n_gpu_layers=0` (the default `-1` puts every layer on Metal) and `op_offload=false`.

*Parameters that now matter:*
- `use_extra_bufts=false`. Today repacking does nothing only because DotProd is missing. **Once DotProd is compiled in, the Q4_0 → q4_0_4x4 repack switches on silently** and makes an anonymous copy about the size of the weights. Issue #19578 shows that memory-mapping plus repacking keeps both copies.
- `load_mode=LLAMA_LOAD_MODE_MMAP` explicitly, because `AUTO` stops memory-mapping if any device lacks support.

*CI guard:* add the binary audit (E1) and fail the build if the load log shows a `CPU_REPACK` buffer or a BLAS or Metal device in the extension build.

**2. Input-copy speculative decoding.** This is the biggest algorithmic gain for a task where the output is mostly a copy of the input.

*Published evidence, all on GPU or servers:*

| Method | Setting | Reported speedup |
|---|---|---|
| Shallow Aggressive Decoding | Transformer, English GEC | ~10× |
| Input-guided Aggressive Decoding | GEC | 7–9×, identical to greedy |
| LLMA | Drafts copied from reference text | >2× |
| Prompt lookup decoding | A100 GPU | 2.4× average |
| Gboard Proofread | Server, TPU | Median latency −39.4% |
| Cursor | Code edits | ~13× |
| DSpark "correction" prompt (llama.cpp #27383) | RTX 4070, F16 | 2.98× |

**No published CPU numbers exist for speculative LLM grammar correction.** On a CPU, the gain is capped by how much a k-token verify batch costs compared with one decode step (experiment E4).

*Estimate grounded in our own numbers [est]:*
- Prefilling 30–60 new tokens costs 0.16 s; decoding 20–60 output tokens costs about 0.33 s.
- When a sentence needs no edit, verifying the copied sentence costs about one prefill of the same length, roughly 0.16 s.
- So 0.49 s becomes about 0.32 s, roughly 1.5×. Sentences with edits fall in between.
- On iPhone this depends on item 1, because the stock build has no fast batch path.

*Why we write it ourselves:*
- llama.cpp's built-in ngram modes live in libcommon (C++). The xcframework doesn't ship libcommon (`LLAMA_BUILD_COMMON=OFF`).
- Their defaults (`ngram-simple` N=12, M=48) are too long for short sentences.
- **Correction to the runtimes report:** the claim that n-gram drafts can't roll back LFM2's state is a policy of libcommon and the server, not a limit of the engine.
  - `common.h` turns on `n_rs_seq` only for draft-model types.
  - In libllama, `n_rs_seq` is a public `llama_context_params` field.
  - LFM2, LFM2MOE and LFM3 are on the rollback allowlist.
  - The prebuilt iOS binary exports `llama_n_rs_seq` and `llama_memory_seq_rm`.

*Design (about 150–250 lines on the C API):*
1. Context setup: `n_rs_seq = K` (8–16), `n_ubatch ≥ K+1`, and logits requested only on the verify positions.
2. The draft is the source tokens from an alignment pointer onward, plus the end-of-turn token after the last source token.
3. The first verify can share a `llama_decode` call with the tail of the prompt: the closing template tokens followed by d1..dK.
4. Accept drafted tokens while the greedy argmax at position i equals draft token i+1. The first mismatch gives the correct token for free.
5. Call `llama_memory_seq_rm(mem, 0, p+n_acc+1, -1)`. #31368 allows rolling back a ubatch of n tokens only if n ≤ `n_rs_seq`+1. If the call returns false, restore our own snapshot and re-decode.
6. After an edit, re-align by searching nearby source positions for the last 1–3 generated tokens, as Input-guided Aggressive Decoding does. If nothing matches, take one plain decode step and try again.

*Memory [est, from config]:*
- About 160 KiB of F32 conv state per snapshot (10 conv layers × 2048 × 2), so about 2.5 MiB at K=16.
- 256 KiB of logits per verified position, so about 4.25 MiB at K=16.
- Keep K+1 below 32.

*Risks:*
- #29085 is still open: creating a context with `n_rs_seq>0` overflowed the graph node budget on LFM2.5-8B-A1B. Master's `graph_max_nodes()` has no LFM2 case, so the 1.2B and LFM3 might hit the same overflow.
- Counter-evidence: DSpark on the 1.2B F16 ran in August, and DSpark forces `n_rs_seq>0`.
- `n_rs_seq` is marked [EXPERIMENTAL].
- The output equals greedy decoding computed in batches. Near-ties can break differently than in token-by-token decoding, so validate with ERRANT F0.5, not byte-identical output.

**3. Prefill as the user types.**
- The keyboard sees the text while it is typed. Decode completed words, up to the last whitespace (the word being typed tokenizes unstably), right after the restored prefix. When the correction triggers, only the tail and the closing template are left to process.
- If the user backspaces into text that is already decoded:
  - use `llama_memory_seq_rm` together with the rollback snapshots, or
  - restore the prefix snapshot and prefill again, which costs what we pay today and should be rare.
- Debounce to word boundaries, run at `.utility` QoS, and cancel on the next keystroke.
- It shares its state machinery with item 2.

**4. Threads and QoS.**
- iPhones have 2 performance cores and 4 efficiency cores.
- ggml can't pin threads on Apple, and every operation ends with a barrier, so one thread on an efficiency core stalls the whole step.
- Use `n_threads=2` for decode and measure `n_threads_batch` from 2 to 4. Liquid's guide (`activeProcessorCount-2`, i.e. 4) and llama.swiftui both mix in efficiency cores.
- Attach a persistent pool (`ggml_threadpool_new` + `llama_attach_threadpool`) with a low `poll` value, so ggml doesn't create a throwaway pool for every graph or spin.
- Call into llama.cpp from `.userInitiated` and keep ggml's priority at NORMAL. On Apple, MEDIUM and above switch to SCHED_FIFO.
- Check worker-thread QoS in Instruments.
- Cheap extra: run a 1-token warm-up decode when the keyboard appears, to fault the memory-mapped weights back in. Never use `mlock`, because locked pages count against the limit.

**5. KV cache.**
- Assumed from LFM2.5-1.2B's config, to be verified: 6 attention layers, 8 KV heads, head dimension 64. That gives about 12 KiB per token in F16, about 12 MiB at n_ctx 1024.
- The 2.6 s cold prefill suggests a prefix of several hundred tokens [est], so q8_0 K/V is a more likely lever than a smaller n_ctx.
- The purpose is headroom for items 2 and 3, not speed. Check quality afterwards.

**6. Model per device.**
- The 350M has about 3.4× fewer parameters than the 1.2B, and QAD Q4_0 files exist for both the 350M and the 230M.
- Reference point: Cactus reports 88 tok/s CPU decode at 56 MB for the 350M on an iPhone 13 mini [vendor].
- Use E7 to set a quality floor.
- LFM3-1.7B is larger (1.05 GB Q4_0), slower and has no drafter. Offer it only as an optional quality mode if E7 shows a clear win.

**7. i8mm.**
- A15 and later add `smmla`, which the Q4_0 batch path uses.
- Using it needs runtime dispatch: `GGML_CPU_ALL_VARIANTS` + `GGML_BACKEND_DL` + `BUILD_SHARED_LIBS`, with one dylib per chip variant. This has not been tested inside an iOS extension.
- Measure build D against build C on an M2 or later Mac first, and proceed only if verify batches gain about 1.2× or more.
- SME/SME2 on A18 and later is reachable only through KleidiAI, which repacks the weights, so it stays off.

**9. Foreground app.**
- DSpark is not for now:
  - its drafter exists only for the 1.2B;
  - using it needs libcommon plus the private `llama-ext.h` ("WIP, breaking changes allowed");
  - Liquid says that "on CPUs and Apple silicon, a quantized target may give little or no speedup";
  - its 2.54× on M4 Max used an F16 target (2.34 GB) and the unmerged #27441 kernels.
- Revisit uzu or MLX only if E9 shows a clear win and the app moves into long-form generation.

**10. Pre-repacked, memory-mappable weights.**
- These would give us repacking's speed without the anonymous copy.
- Mainline removed the Q4_0_4_4, 4_8 and 8_8 file types.
- ik_llama.cpp has memory-mappable interleaved types and supports LFM2.5. Its iOS build, rollback support, and whether converting from Q4_0 is lossless are all unverified.
- Research this only after items 1–3 ship, and only if E4 shows that batch cost is the bottleneck.

### 3.4 What we skip, and why

- **ANE, Core ML or Core AI in the keyboard.**
  - The iOS 27 release notes (174796039) say ANE memory "is now attributed to your app process".
  - Forum reports show footprints of several GB.
  - Measured footprints are 98–256 MB, and the first load takes 77 s.
- **DSpark in the keyboard.**
  - The drafter has 295.7M parameters (594 MB F16, 317 MB Q8_0, 176 MB Q4_K_M) and needs extra memory that is not file-backed.
  - It is not reachable through `llama.h`, and a drafter exists only for the 1.2B.
  - Liquid says quantized CPU targets gain little.
- **A 230M or 350M LFM model as the draft model.** It adds a sequential forward pass per token plus its own buffers, while drafting from the input is free. [est] It would lose.
- **MLX, uzu, LiteRT-LM, ExecuTorch, ORT-GenAI, MLC or Cactus in the keyboard.** Each fails on how it holds weights in memory or on license (see the table).
- **KleidiAI, SME2 or runtime repacking.** All make anonymous copies of the weights.
- **Other quantization formats.** Keep QAD Q4_0, which was trained for the Q4_0 grid. The alternatives are worse here:
  - Q4_K has no tinyBLAS batch path.
  - IQ4_NL has no ARM tinyBLAS path and uses nrows=1.
  - Q8_0 reads about 1.9× the bytes per token.
- **The tagger model** (LFM2.5-Encoder-350M-Spellchecker).
  - CoNLL-14 F0.5 is 44.6 with recall 18.9.
  - Its tag head doesn't run in llama.cpp.
  - It peaked at 746 MiB in LiteRT.
  - Its license is lfm1.0.
- **Diff or edit-span output formats.** They need retraining, and with input-copy drafting a full rewrite costs about the same.
- **Free extra worth doing:** cache corrections by sentence hash.

### 3.5 What to expect overall [est, unmeasured]

On the M1 runner as a stand-in, items 2 and 3 could bring perceived latency from 0.49 s to roughly 0.2–0.3 s for typical sentences, and lower for sentences with nothing to fix.

On iPhone, the stock build is probably slower than the Mac figure suggests today. Item 1 is the precondition for every other gain there. Section 4 is how we confirm all of this.

### 3.6 Licensing note

- llama.cpp is MIT, an OSI license.
- **The LFM weights are under lfm1.0, which is not OSI** and has a commercial-use threshold in Section 5. If a fully OSI stack matters, the gap is the model, not the runtime.
- Cactus is ruled out by its license.
- The license of Core AI's conversion tooling is unconfirmed.
- Foundation Models is a proprietary model in the OS; our app stays MIT.

---

## 4. What to benchmark

### 4.1 On an Apple Silicon Mac (can start now, mostly in CI)

**E1. Binary audit, run on every llama.cpp bump.**
`xcrun llvm-objdump -d --mattr=+dotprod,+i8mm,+fullfp16 <xcframework>/ios-arm64/llama.framework/llama | grep -cE '\s(sdot|udot)\s'` (and the same for `smmla`).
- Pass: the `sdot` count is above 0.
- The load log shows no `CPU_REPACK`, BLAS or Metal buffer in the extension build.

**E2. Mac stand-in for the iPhone flag change.** All builds are CPU-only, memory-mapped, `use_extra_bufts=false`, `GGML_METAL=OFF`.

| Build | `GGML_CPU_ARM_ARCH` | BLAS | Notes |
|---|---|---|---|
| A | `armv8-a` | ON | Reproduces the stock iOS slice (`apple-a7`) |
| B | `armv8-a` | OFF | |
| C | `armv8.4-a+dotprod+fp16` | OFF | Proposed |
| D | `armv8.6-a+dotprod+i8mm+fp16` | OFF | M2 or later only; the GitHub M1 runner lacks i8mm |

- Run our 0.49 s sentence harness on each build: end to end, decode ms/token, and prefill for 32 and 64 new tokens, at 2 and 3 threads.
- Use `llama-bench -m <Q4_0> -ngl 0 -mmp 1 -t 2,3 -ub 32 -p 16,32,64 -n 32 -r 5` only if that build lets repacking be turned off. Otherwise use the harness alone.
- **The A→C ratio is our best estimate of the iPhone gain before we have a device.**

**E3. Memory.** The harness reads `phys_footprint` (`task_info TASK_VM_INFO`) after every `llama_decode`, plus `footprint <pid>` / `vmmap --summary` to split dirty from clean memory. Cases and expected results:
- Build A with exactly 31, 32 and 64 new tokens: +64 MiB at 32 tokens or more.
- Build C with `use_extra_bufts` true vs false: about +660 MB vs 0.
- n_ctx 1024 with F16 vs q8_0 KV.
- Speculative decoding with K = 8, 16 and 24.
- Gate: the whole stack's anonymous peak leaves at least 10 MB of headroom below the 77 MB keyboard limit (66 MB on iOS 12–14).

**E4. Cost of a verify batch.**
- After restoring the prefix and adding a 40-token sentence, time `llama_decode` for k = 1, 2, 4, 8, 12, 16 and 24 with logits on every position, on builds A and C, at 2 and 3 threads.
- Report cost(k) / cost(1).
- Pick the largest K with cost(K)/cost(1) ≤ about K/2.
- If cost(8)/cost(1) is above 6, speculative decoding won't pay off on that build.

**E5. Speculative decoding prototype.**
- Data:
  - BEA-2019 W&I+LOCNESS dev;
  - CoNLL-2014 test;
  - about 500 keyboard-style sentences of our own, with about half needing no edit.
- Measure: accepted tokens per verify, verify calls per sentence, and p50 and p95 latency against plain greedy decoding.
- Quality gate: the share of outputs identical to plain greedy, and the ERRANT F0.5 change, which should be about 0.
- Robustness: create contexts with `n_rs_seq` = 8, 16 and 24 for the 1.2B, 350M, 230M and LFM3-1.7B (the #29085 risk), and log every `llama_memory_seq_rm` call that returns false.

**E6. Threads.** Measure decode and batch speed at 1–4 threads on an M-series Mac. Treat it as directional only, since the core mix differs from the iPhone's 2 performance + 4 efficiency cores.

**E7. Model size.**
- Run the 230M, 350M, 1.2B and LFM3-1.7B on build C: latency plus ERRANT F0.5 on the E5 set.
- Use the results to set a quality floor for a "fast mode" and a per-device default.

**E8. Prefill-as-you-type replay.** Replay typing traces that include backspaces. Measure tokens already decoded when the correction triggers, latency after the trigger, and wasted tokens.

**E9. Foreground engine (low priority).**
- Compare llama.cpp Metal vs MLX Swift vs uzu on LFM2.5-1.2B with our prompt shape: prefix restore, 30–60 tokens in, 20–60 out.
- Also run llama.cpp Metal with input-copy speculation.

### 4.2 Only a physical iPhone can answer

- **Real speedup of the DotProd build per chip** (A13, A15, A17/A18, A19). `llama_print_system_info()` should show `DOTPROD = 1` on the device.
- **Whether i8mm runtime dispatch works in a keyboard.** Do separately loaded per-variant dylibs load inside the extension?
- **Real memory limit and our true peak.** Measure the actual jetsam limit and our peak `phys_footprint` inside the keyboard on the iOS versions we target (Xcode memory gauge, `os_proc_available_memory()`, MetricKit).
- **Core placement and heat.** Which cores the threads land on, whether ggml worker threads inherit QoS (Instruments), and thermal behaviour under sustained typing.
- **Page eviction.** Does iOS evict the memory-mapped 696 MB file while the user is in other apps, how slow is the first correction afterwards, and does the warm-up decode fix it?
- **Access from inside a keyboard.** Can it reach the Foundation Models XPC service (with and without Full Access), Metal, or the ANE / Core AI?
- **Energy per correction** on battery.
- **Latency on the oldest supported device**, to set the per-device model policy.

---

## Sources

**Liquid AI documentation, blogs and paper**
- https://docs.liquid.ai/deployment/on-device/llama-cpp/migrating-from-leap-sdk
- https://docs.liquid.ai/deployment/on-device/llama-cpp/mobile
- https://docs.liquid.ai/deployment/on-device/llama-cpp/mobile.md
- https://docs.liquid.ai/lfm/help/deprecations.md
- https://docs.liquid.ai/deployment/on-device/sdk/overview
- https://docs.liquid.ai/deployment/on-device/leap-sdk-changelog
- https://docs.liquid.ai/leap/edge-sdk/overview
- https://docs.liquid.ai/lfm/help/faqs.md
- https://docs.liquid.ai/guides/hardware-evaluation.md
- https://docs.liquid.ai/lfm/models/complete-library.md
- https://docs.liquid.ai/deployment/on-device/onnx.md
- https://docs.liquid.ai/lfm/models/lfm3-1.7b
- https://docs.liquid.ai/deployment/on-device/llama-cpp.md
- https://docs.liquid.ai/lfm/key-concepts/speculative-decoding.md
- https://www.liquid.ai/blog/qad
- https://www.liquid.ai/blog/how-liquid-ai-uses-executorch-to-power-efficient-flexible-on-device-intelligence
- https://www.liquid.ai/blog/lfm2-5-1-2b-thinking-on-device-reasoning-under-1gb
- https://www.liquid.ai/blog/lfm2-5-350m-no-size-left-behind
- https://www.liquid.ai/blog/lfm2.5-dspark
- https://github.com/Liquid4All/onnx-export
- https://arxiv.org/abs/2511.23404

**Model cards and conversions**
- https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct
- https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct/raw/main/config.json
- https://huggingface.co/LiquidAI/LFM3-1.7B
- https://huggingface.co/LiquidAI/LFM3-1.7B-GGUF
- https://huggingface.co/LiquidAI/LFM3-1.7B-MLX-4bit
- https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-DSpark
- https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-DSpark-GGUF
- https://huggingface.co/tugot17/LFM2.5-1.2B-Instruct-DSpark-5L-GGUF
- https://huggingface.co/LiquidAI/LFM2.5-Encoder-350M-Spellchecker
- https://huggingface.co/LiquidAI/LFM2.5-Encoder-350M-GGUF
- https://huggingface.co/litert-community/LFM2.5-Encoder-350M-Spellchecker
- https://huggingface.co/litert-community/LFM2.5-350M
- https://huggingface.co/mlboydaisuke/LFM2.5-1.2B-CoreAI
- https://huggingface.co/mlboydaisuke/LFM2.5-350M-ExecuTorch
- https://huggingface.co/software-mansion/react-native-executorch-lfm2.5-1.2B-instruct
- https://huggingface.co/runanywhere/LFM2.5-350M_ANE
- https://huggingface.co/experimentalmachines/LFM2.5-1.2B-Instruct-ExecuTorch

**llama.cpp source, docs and releases**
- https://github.com/ggml-org/llama.cpp/releases
- https://github.com/ggml-org/llama.cpp/tags
- https://github.com/ggml-org/llama.cpp/releases/tag/v0.7.0
- https://github.com/ggml-org/llama.cpp/releases/download/b12017/llama-b12017-xcframework.zip
- https://github.com/ggml-org/llama.cpp/blob/master/build-xcframework.sh
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/CMakeLists.txt
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/CMakeLists.txt
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cpu/CMakeLists.txt
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cpu/ggml-cpu-impl.h
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cpu/ggml-cpu.c
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cpu/ggml-cpu.cpp
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cpu/llamafile/sgemm.cpp
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-cpu/repack.cpp
- https://github.com/ggml-org/llama.cpp/blob/master/ggml/src/ggml-blas/ggml-blas.cpp
- https://github.com/ggml-org/llama.cpp/blob/master/include/llama.h
- https://github.com/ggml-org/llama.cpp/blob/master/src/llama-model.cpp
- https://github.com/ggml-org/llama.cpp/blob/master/src/llama-context.cpp
- https://github.com/ggml-org/llama.cpp/blob/master/src/llama-arch.cpp
- https://github.com/ggml-org/llama.cpp/blob/master/src/llama-ext.h
- https://github.com/ggml-org/llama.cpp/blob/master/common/common.h
- https://github.com/ggml-org/llama.cpp/blob/master/docs/speculative.md
- https://github.com/ggml-org/llama.cpp/blob/master/docs/build.md

**llama.cpp pull requests and issues**
- https://github.com/ggml-org/llama.cpp/pull/17030
- https://github.com/ggml-org/llama.cpp/pull/17241
- https://github.com/ggml-org/llama.cpp/pull/19164
- https://github.com/ggml-org/llama.cpp/pull/19356
- https://github.com/ggml-org/llama.cpp/pull/19360
- https://github.com/ggml-org/llama.cpp/pull/22673
- https://github.com/ggml-org/llama.cpp/pull/23780
- https://github.com/ggml-org/llama.cpp/pull/25173
- https://github.com/ggml-org/llama.cpp/pull/27383
- https://github.com/ggml-org/llama.cpp/pull/27441
- https://github.com/ggml-org/llama.cpp/pull/27483
- https://github.com/ggml-org/llama.cpp/pull/29085
- https://github.com/ggml-org/llama.cpp/pull/29219
- https://github.com/ggml-org/llama.cpp/pull/29339
- https://github.com/ggml-org/llama.cpp/pull/29454
- https://github.com/ggml-org/llama.cpp/pull/29862
- https://github.com/ggml-org/llama.cpp/pull/30873
- https://github.com/ggml-org/llama.cpp/pull/31252
- https://github.com/ggml-org/llama.cpp/pull/31350
- https://github.com/ggml-org/llama.cpp/pull/31368
- https://github.com/ggml-org/llama.cpp/issues/16761
- https://github.com/ggml-org/llama.cpp/issues/19578
- https://github.com/ggml-org/llama.cpp/issues/28425

**LLVM, Apple platform and hardware**
- https://github.com/llvm/llvm-project/blob/main/clang/lib/Driver/ToolChains/Arch/AArch64.cpp
- https://github.com/llvm/llvm-project/blob/main/llvm/lib/Target/AArch64/AArch64Processors.td
- https://appleinsider.com/articles/26/06/08/ios-27-keeps-iphone-11-and-newer-compatibility
- https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes
- https://developer.apple.com/forums/thread/833575
- https://developer.apple.com/forums/thread/831314
- https://developer.apple.com/forums/thread/839109
- https://developer.apple.com/forums/thread/851698
- https://developer.apple.com/apple-intelligence/foundation-models-adapter
- https://developer.apple.com/documentation/coreai
- https://developer.apple.com/videos/play/wwdc2026/324/
- https://github.com/apple/coreai-models
- https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/PrioritizeWorkWithQoS.html
- https://support.apple.com/en-us/111831
- https://www.apple.com/iphone-18-pro/specs/

**Other runtimes**
- https://github.com/ml-explore/mlx-swift/releases
- https://github.com/ml-explore/mlx-swift-lm/tree/main/Libraries/MLXLLM/Models
- https://github.com/ml-explore/mlx-lm/tree/main/mlx_lm/models
- https://github.com/ml-explore/mlx/blob/main/mlx/io/load.cpp
- https://atomgradient.github.io/MLXLayerStream/paper.pdf
- https://github.com/trymirai/uzu
- https://github.com/trymirai/uzu/blob/main/LICENSE
- https://github.com/trymirai/uzu/blob/main/crates/uzu-engine/src/backends/cpu/kernel/matmul/kernel.rs
- https://trymirai.com/local-models
- https://github.com/john-rocky/CoreML-LLM
- https://github.com/Anemll/Anemll
- https://github.com/pytorch/executorch/releases
- https://github.com/pytorch/executorch/tree/main/examples/models/lfm2
- https://github.com/pytorch/executorch/pull/9297
- https://github.com/microsoft/onnxruntime/releases
- https://github.com/microsoft/onnxruntime-genai/releases
- https://github.com/mlc-ai/mlc-llm
- https://github.com/google-ai-edge/LiteRT-LM
- https://github.com/cactus-compute/cactus
- https://github.com/cactus-compute/cactus/blob/main/LICENSE
- https://github.com/alibaba/MNN/releases
- https://github.com/alibaba/MNN/blob/master/transformers/llm/export/utils/model_mapper.py
- https://github.com/ikawrakow/ik_llama.cpp
- https://docs.nexa.ai/en/nexa-sdk-ios/overview
- https://huggingface.co/blog/runanywhere/metalrt-fastest-inference-apple-silicon
- https://huggingface.co/blog/mistral-coreml

**Benchmarks and measurement papers**
- https://github.com/john-rocky/apple-silicon-llm-bench
- https://github.com/john-rocky/apple-silicon-llm-bench/blob/main/README.md
- https://github.com/john-rocky/apple-silicon-llm-bench/blob/main/LEADERBOARD.md
- https://github.com/john-rocky/apple-silicon-llm-bench/blob/main/RESULTS.md
- https://github.com/john-rocky/apple-silicon-llm-bench/blob/main/docs/cactus-vs-litert.md
- https://github.com/john-rocky/apple-silicon-llm-bench/blob/main/ios/BenchmarkApp/Sources/Runtimes/LlamaCppRuntime.swift
- https://github.com/john-rocky/apple-silicon-llm-bench/blob/main/results/raw/2026-08-15-muse-glimmer-30b-3way/README.md
- https://dev.to/john-rocky/on-device-llm-on-iphone-which-runtime-is-fastest-mlx-vs-llamacpp-vs-litert-lm-vs-coreml-1b42
- https://dev.to/john-rocky/iphone-on-device-llm-the-gpu-wins-the-sprint-the-neural-engine-wins-the-marathon-42lo
- https://rickytakkar.com/blog_russet_mlx_benchmark.html
- https://trymirai.com/metrics
- https://www.runanywhere.ai/blog/metalrt-fastest-llm-decode-engine-apple-silicon
- https://aitamer.news/posts/uzu-rust-inference-apple-silicon-speculative-decoding/
- https://developers.google.com/edge/litert-lm/overview
- https://developers.googleblog.com/en/blazing-fast-on-device-genai-with-litert-lm/
- https://pypi.org/project/optimum-executorch/
- https://arxiv.org/abs/2605.08195
- https://arxiv.org/abs/2505.06461
- https://arxiv.org/abs/2603.23640
- https://arxiv.org/abs/2511.05502
- https://medium.com/@andreask_75652/llama-cpp-performance-apple-silicon-051241dd6eae

**Speculative decoding and grammar-correction literature**
- https://github.com/apoorvumang/prompt-lookup-decoding
- https://arxiv.org/abs/2106.04970
- https://arxiv.org/abs/2205.10350
- https://arxiv.org/abs/2304.04487
- https://arxiv.org/abs/2406.04523
- https://cursor.com/blog/instant-apply
- https://arxiv.org/abs/2005.12592
- https://aclanthology.org/2023.emnlp-main.619
