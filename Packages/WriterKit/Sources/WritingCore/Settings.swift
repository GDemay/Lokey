import Foundation

public enum AutocorrectMode: String, Codable, CaseIterable, Sendable {
    /// Never correct while typing.
    case off
    /// Show the fixed sentence in the toolbar; one tap applies it.
    case suggest
    /// Apply small fixes automatically when a sentence ends; one tap undoes.
    case automatic

    public var title: String {
        switch self {
        case .off: return "Off"
        case .suggest: return "Suggest"
        case .automatic: return "Automatic"
        }
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var selectedModelID: String?
    public var keyboardLayout: KeyboardLayout = .automatic
    public var autocorrectMode: AutocorrectMode = .automatic
    /// Fixes that change more than this (1 - similarity) are offered as suggestions even in automatic mode.
    public var automaticMaxChange: Double = 0.2
    public var hapticFeedback: Bool = true
    public var keyClickSound: Bool = false
    public var showChangesBeforeApplying: Bool = true
    public var spellingSuggestions: Bool = true
    public var useGPU: Bool = false
    public var hasCompletedOnboarding: Bool = false
    public var setupVersion: Int = 0
    public var setupStep: Int = 0
    public var keyboardCheckID: String?

    public init() {}

    // Decode leniently so adding a setting never resets the others.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.Defaults()
        selectedModelID = try c.decodeIfPresent(String.self, forKey: .selectedModelID)
        keyboardLayout = try c.decodeIfPresent(KeyboardLayout.self, forKey: .keyboardLayout) ?? .automatic
        autocorrectMode = try c.decodeIfPresent(AutocorrectMode.self, forKey: .autocorrectMode) ?? d.autocorrectMode
        automaticMaxChange = try c.decodeIfPresent(Double.self, forKey: .automaticMaxChange) ?? d.automaticMaxChange
        hapticFeedback = try c.decodeIfPresent(Bool.self, forKey: .hapticFeedback) ?? d.hapticFeedback
        keyClickSound = try c.decodeIfPresent(Bool.self, forKey: .keyClickSound) ?? d.keyClickSound
        showChangesBeforeApplying = try c.decodeIfPresent(Bool.self, forKey: .showChangesBeforeApplying) ?? d.showChangesBeforeApplying
        spellingSuggestions = try c.decodeIfPresent(Bool.self, forKey: .spellingSuggestions) ?? d.spellingSuggestions
        useGPU = try c.decodeIfPresent(Bool.self, forKey: .useGPU) ?? d.useGPU
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        setupVersion = try c.decodeIfPresent(Int.self, forKey: .setupVersion) ?? 0
        setupStep = try c.decodeIfPresent(Int.self, forKey: .setupStep) ?? 0
        keyboardCheckID = try c.decodeIfPresent(String.self, forKey: .keyboardCheckID)
    }

    private struct Defaults {
        let autocorrectMode = AutocorrectMode.automatic
        let automaticMaxChange = 0.2
        let hapticFeedback = true
        let keyClickSound = false
        let showChangesBeforeApplying = true
        let spellingSuggestions = true
        let useGPU = false
        let hasCompletedOnboarding = false
    }
}

/// Written by the keyboard each time it appears, so the app can show whether setup is complete.
/// (Without Full Access the keyboard cannot write it, which is itself the signal.)
public struct KeyboardStatus: Codable, Equatable, Sendable {
    public var lastSeen: Date
    public var hasFullAccess: Bool
    public var modelName: String?
    public var modelID: String?
    public var checkID: String?
    public var footprintMB: Double?
    /// The extension's highest footprint so far; this is what must stay under the memory limit.
    public var peakFootprintMB: Double?

    public init(lastSeen: Date, hasFullAccess: Bool, modelName: String? = nil, footprintMB: Double? = nil,
                peakFootprintMB: Double? = nil, modelID: String? = nil, checkID: String? = nil) {
        self.lastSeen = lastSeen
        self.hasFullAccess = hasFullAccess
        self.modelName = modelName
        self.modelID = modelID
        self.checkID = checkID
        self.footprintMB = footprintMB
        self.peakFootprintMB = peakFootprintMB
    }

    public func verifies(checkID: String, modelID: String?) -> Bool {
        self.checkID == checkID && hasFullAccess && modelID != nil && self.modelID == modelID
    }
}

/// Settings shared between the app and the keyboard through the App Group's UserDefaults.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "settings.v1"
    private let statusKey = "keyboard.status.v1"

    public func loadKeyboardStatus() -> KeyboardStatus? {
        defaults.data(forKey: statusKey).flatMap { try? JSONDecoder().decode(KeyboardStatus.self, from: $0) }
    }

    public func saveKeyboardStatus(_ status: KeyboardStatus) {
        if let data = try? JSONEncoder().encode(status) { defaults.set(data, forKey: statusKey) }
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public static func shared(appGroupID: String = Brand.appGroupID) -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: appGroupID) ?? .standard)
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }

    public func update(_ change: (inout AppSettings) -> Void) {
        var settings = load()
        change(&settings)
        save(settings)
    }
}
