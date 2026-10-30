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
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? UInt64(info.phys_footprint) : nil
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
