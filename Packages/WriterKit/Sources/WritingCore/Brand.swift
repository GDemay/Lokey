import Foundation

/// Product-wide identifiers shared by the app, the keyboard extension and tests.
public enum Brand {
    public static let name = "Lokey"
    public static let tagline = "Fix your English anywhere. On-device, free, private."
    public static let bundlePrefix = "com.gdemay.lokey"
    /// Must match the App Group in both targets' entitlements.
    public static let appGroupID = "group.com.gdemay.lokey"
    public static let keyboardBundleID = bundlePrefix + ".keyboard"
    public static let sourceURL = URL(string: "https://github.com/GDemay/Lokey")!
}
