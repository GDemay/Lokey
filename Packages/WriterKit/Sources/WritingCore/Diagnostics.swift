#if canImport(os)
import os
#endif

/// On-device diagnostics in the system log (Console.app, `log show`), never sent anywhere.
/// Only timings, token counts, memory and model names: never pass user text.
public enum Diagnostics {
    #if canImport(os)
    private static let logger = Logger(subsystem: Brand.bundlePrefix, category: "inference")
    #endif

    public static func log(_ message: @autoclosure () -> String) {
        #if canImport(os)
        let text = message()
        logger.notice("\(text, privacy: .public)")
        #endif
    }
}
