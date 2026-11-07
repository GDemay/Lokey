import Foundation

enum CasualWording {
    private static let expansions = [
        "going to": "gonna",
        "want to": "wanna",
        "kind of": "kinda",
        "disponible": "dispo",
        "cinéma": "ciné",
        "tu as": "t'as",
        "tu es": "t'es",
        "je suis": "j'suis",
        "s'il te plaît": "stp",
    ]
    private static let phrases = try! NSRegularExpression(
        pattern: #"\b(?:going to|gonna|want to|wanna|kind of|kinda|disponible|dispo|cinéma|ciné|tu as|t['’]as|tu es|t['’]es|je suis|j['’]suis|s['’]il te plaît|stp)\b"#,
        options: .caseInsensitive
    )
    private static let casualOpeners: Set<String> = [
        "ah", "bah", "désolé", "franchement", "hey", "lol", "mdr", "nah", "ouais", "tbh", "yeah",
    ]
    // Common sentence starts where a capital is a style choice. Leave proper names and English I alone.
    private static let lowercaseStarts = casualOpeners.union([
        "but", "can", "can't", "could", "he", "how", "if", "see", "she", "thanks", "that", "they",
        "we", "what", "when", "where", "you", "allez", "bon", "j", "je", "mais", "on", "t", "tu",
    ])

    static func preserve(in output: String, from source: String) -> String {
        let text = preservePhrases(in: output, from: source)
        guard let first = text.first, let original = source.first else { return text }
        let word = text.prefix(while: \.isLetter)
        let initial = word.lowercased()
        let opener = source.prefix(while: \.isLetter)
        var restored = text
        if lowercaseStarts.contains(initial) {
            if initial == opener.lowercased() {
                restored = String(opener + text.dropFirst(word.count))
            } else if original.isLowercase && first.isUppercase {
                restored = first.lowercased() + text.dropFirst()
            }
        }
        if casualOpeners.contains(opener.lowercased()),
           source.dropFirst(opener.count).first?.isWhitespace == true,
           restored.prefix(opener.count).lowercased() == opener.lowercased() {
            let after = restored.index(restored.startIndex, offsetBy: opener.count)
            if after < restored.endIndex && restored[after] == "," {
                restored.remove(at: after)
            }
        }
        return restored
    }

    private static func preservePhrases(in output: String, from source: String) -> String {
        func matches(_ text: String) -> [(range: Range<String.Index>, phrase: String, key: String)] {
            phrases.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
                guard let range = Range($0.range, in: text) else { return nil }
                let phrase = String(text[range])
                let normalized = phrase.lowercased().replacingOccurrences(of: "’", with: "'")
                return (range, phrase, expansions[normalized] ?? normalized)
            }
        }
        let before = matches(source)
        guard !before.isEmpty else { return output }
        let after = matches(output)
        // Preserve the form only when the recognized phrases have the same sequence.
        guard before.map(\.key) == after.map(\.key) else { return output }
        var restored = ""
        var cursor = output.startIndex
        for (original, corrected) in zip(before, after) where original.phrase != corrected.phrase {
            restored += output[cursor..<corrected.range.lowerBound]
            restored += original.phrase
            cursor = corrected.range.upperBound
        }
        return restored + output[cursor...]
    }
}
