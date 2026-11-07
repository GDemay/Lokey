import Foundation

public enum KeyboardLayout: String, Codable, CaseIterable, Sendable {
    case automatic, qwerty, azerty, qwertz

    public var title: String {
        switch self {
        case .automatic: return "Automatic (\(resolved().rawValue.uppercased()))"
        default: return rawValue.uppercased()
        }
    }

    public func resolved(languages: [String] = Locale.preferredLanguages) -> KeyboardLayout {
        guard self == .automatic else { return self }
        let language = languages.first?.lowercased() ?? "en"
        if language.hasPrefix("fr"), !language.hasPrefix("fr-ca") { return .azerty }
        if language.hasPrefix("de") { return .qwertz }
        return .qwerty
    }

    public var letterRows: [String] {
        switch resolved() {
        case .azerty: return ["azertyuiop", "qsdfghjklm", "wxcvbn’"]
        case .qwertz: return ["qwertzuiop", "asdfghjkl", "yxcvbnm"]
        default: return ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        }
    }

    public static func alternatives(for character: String) -> [String] {
        switch character {
        case "a": return ["à", "â", "ä", "á", "æ"]
        case "c": return ["ç"]
        case "e": return ["é", "è", "ê", "ë"]
        case "i": return ["î", "ï", "í"]
        case "o": return ["ô", "ö", "ó", "œ"]
        case "u": return ["ù", "û", "ü", "ú"]
        case "y": return ["ÿ"]
        case "s": return ["ß"]
        default: return []
        }
    }
}
