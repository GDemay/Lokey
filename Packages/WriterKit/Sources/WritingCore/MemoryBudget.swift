import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(os)
import os
#endif

/// Memory accounting for running a model inside a keyboard extension, where the system
/// kills the process above a small limit. Model weights are memory-mapped read-only and
/// are not counted in the footprint; what counts is the KV cache, compute buffers and UI.
public enum MemoryBudget {
    /// Bytes the process can still allocate before hitting its limit (iOS), or nil if unknown.
    public static func availableBytes() -> UInt64? {
        #if os(iOS)
        let value = os_proc_available_memory()
        return value > 0 ? UInt64(value) : nil
        #else
        return nil
        #endif
    }

    /// Current physical footprint (what the jetsam limit is compared against), if available.
    public static func footprintBytes() -> UInt64? {
        #if canImport(Darwin)
        return taskVMInfo().map { UInt64($0.phys_footprint) }
        #elseif os(Linux)
        // Anonymous resident memory: the closest Linux analogue (excludes clean file-backed pages).
        // procfs reports a size of 0, so read it with stdio rather than Foundation.
        guard let file = fopen("/proc/self/status", "r") else { return nil }
        defer { fclose(file) }
        var buffer = [CChar](repeating: 0, count: 256)
        while fgets(&buffer, Int32(buffer.count), file) != nil {
            let line = String(cString: buffer)
            if line.hasPrefix("RssAnon:") {
                let kb = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).compactMap { UInt64($0) }.first ?? 0
                return kb * 1024
            }
        }
        return nil
        #else
        return nil
        #endif
    }

    /// Highest physical footprint this process has reached. The system kills an extension the
    /// moment it crosses its limit, so the peak (not the current value) is what must fit.
    public static func peakFootprintBytes() -> UInt64? {
        #if canImport(Darwin)
        guard let peak = taskVMInfo()?.ledger_phys_footprint_peak, peak > 0 else { return nil }
        return UInt64(peak)
        #else
        return nil
        #endif
    }

    /// Returns freed heap pages to the system. Loading a model frees large temporary buffers
    /// (GGUF metadata, tokenizer tables) that the allocator would otherwise keep counted.
    public static func releaseFreeMemory() {
        #if canImport(Darwin)
        _ = malloc_zone_pressure_relief(nil, 0)
        #elseif os(Linux)
        _ = glibcMallocTrim(0)
        #endif
    }

    /// "footprint 45.1 MB, peak 61.0 MB" for diagnostics logs.
    public static func summary() -> String {
        func mb(_ bytes: UInt64?) -> String { bytes.map { String(format: "%.1f MB", Double($0) / 1_048_576) } ?? "n/a" }
        return "footprint \(mb(footprintBytes())), peak \(mb(peakFootprintBytes()))"
    }

    #if canImport(Darwin)
    private static func taskVMInfo() -> task_vm_info_data_t? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? info : nil
    }
    #endif

    /// Estimated extra footprint to run `model` with keyboard settings, from measurements
    /// (see LlamaRuntimeTests.testKeyboardMemoryFootprint).
    public static func estimatedKeyboardCost(for model: ModelInfo) -> UInt64 {
        switch model.tier {
        case .tiny: return 24 << 20
        case .fast: return 28 << 20
        case .balanced: return 40 << 20
        case .large: return 56 << 20
        }
    }
}

#if os(Linux)
/// glibc's malloc_trim (declared in malloc.h, which the Glibc module does not export).
@_silgen_name("malloc_trim")
private func glibcMallocTrim(_ pad: Int) -> Int32
#endif
