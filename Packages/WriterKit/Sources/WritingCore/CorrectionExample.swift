import Foundation

/// Only the changed words and the context needed to understand a known rule are saved.
public struct CorrectionExample: Codable, Hashable, Sendable {
    public let before: String
    public let after: String
    public let languageCode: String?
    public let lesson: Lesson

    public enum Lesson: String, Codable, Sendable {
        case agreement, frenchAgreement, plural, article, contraction, pronounI, capitalization, punctuation, accent
        case theyre, youre, its, other

        public var title: String {
            switch self {
            case .agreement, .frenchAgreement: return "Subject and verb"
            case .plural: return "Singular and plural"
            case .article: return "A and an"
            case .contraction: return "Contractions"
            case .pronounI, .capitalization: return "Capital letters"
            case .punctuation: return "Punctuation"
            case .accent: return "Accent marks"
            case .theyre, .youre, .its: return "Commonly confused words"
            case .other: return "Word or phrase"
            }
        }

        public var tip: String {
            switch self {
            case .agreement: return "Match the verb to its subject. For example, “she has” and “they have.”"
            case .frenchAgreement: return "In French, the verb ending depends on the subject. For example, “je peux” and “il peut.”"
            case .plural: return "Use the plural form of a countable noun after a number greater than one."
            case .article: return "Use “a” before a consonant sound and “an” before a vowel sound."
            case .contraction: return "Use an apostrophe to mark the letters left out of a contraction."
            case .pronounI: return "Always capitalize the pronoun “I,” including in contractions such as “I’m.”"
            case .capitalization: return "Notice which letters changed case in the corrected version."
            case .punctuation: return "Read both versions aloud and notice how the punctuation separates ideas."
            case .accent: return "Notice where the corrected spelling uses an accent mark."
            case .theyre: return "“They’re” means “they are.” “Their” shows possession. “There” can refer to a place."
            case .youre: return "“You’re” means “you are.” “Your” shows possession."
            case .its: return "“It’s” means “it is” or “it has.” “Its” shows possession."
            case .other: return "Try using the corrected form in another sentence."
            }
        }
    }

    public static func extract(from original: String, corrected: String, languageHint: String? = nil) -> [Self] {
        guard original != corrected else { return [] }
        let before = TextChunker.sentences(original)
        let after = TextChunker.sentences(corrected)
        if before.count == after.count {
            return zip(before, after).flatMap { old, new in
                changes(from: old, to: new, languageHint: languageHint)
            }
        }
        // An edit to punctuation can change where a sentence ends.
        return changes(from: original, to: corrected, languageHint: languageHint)
    }

    private static func changes(from before: String, to after: String, languageHint: String?) -> [Self] {
        guard before != after else { return [] }
        let languageCode = languageHint ?? CorrectionLanguage.historyLanguage(in: before)
        var corrections: [Self] = []
        var context = ""
        var removed = ""
        var inserted = ""
        func appendChange() {
            let old = removed.trimmingCharacters(in: .whitespacesAndNewlines)
            let new = inserted.trimmingCharacters(in: .whitespacesAndNewlines)
            if let correction = classify(before: old, after: new, preceding: context, languageCode: languageCode) {
                corrections.append(correction)
            }
            removed = ""
            inserted = ""
        }
        for segment in TextDiff.diff(before, after) {
            switch segment.kind {
            case .equal:
                appendChange()
                context = segment.text
            case .removed:
                removed += segment.text
            case .inserted:
                inserted += segment.text
            }
        }
        appendChange()
        return corrections
    }

    private static func classify(before: String, after: String, preceding: String, languageCode: String?) -> Self? {
        guard before != after, [before, after].allSatisfy({
            $0.count <= 64 && !$0.contains(where: \.isNewline) && $0.split(whereSeparator: \.isWhitespace).count <= 5
        }) else { return nil }
        let oldSpelling = before.replacingOccurrences(of: "’", with: "'")
        let newSpelling = after.replacingOccurrences(of: "’", with: "'")
        guard oldSpelling != newSpelling else { return nil }
        let old = oldSpelling.lowercased(), new = newSpelling.lowercased()
        func example(_ lesson: Lesson, subject: String? = nil) -> Self {
            let prefix = subject.map { $0 + " " } ?? ""
            return Self(before: prefix + before, after: prefix + after, languageCode: languageCode, lesson: lesson)
        }
        if old == new {
            return example(languageCode == "en" && (old == "i" || old.hasPrefix("i'")) ? .pronounI : .capitalization)
        }
        if (old + new).allSatisfy(\.isPunctuation) {
            return example(.punctuation)
        }
        if old.folding(options: .diacriticInsensitive, locale: nil) == new.folding(options: .diacriticInsensitive, locale: nil) {
            return example(.accent)
        }
        let previous = preceding.last?.isWhitespace == true
            ? preceding.split(whereSeparator: \.isWhitespace).last.map(String.init) : nil
        if languageCode == "fr", let previous, frenchSubjects.contains(previous.lowercased()),
           frenchVerbForms.contains(where: { $0.contains(old) && $0.contains(new) }) {
            return example(.frenchAgreement, subject: previous)
        }
        guard languageCode == "en" else { return example(.other) }
        if let previous, subjects.contains(previous.lowercased()),
           verbForms.contains(where: { $0.contains(old) && $0.contains(new) }) {
            return example(.agreement, subject: previous)
        }
        if let previous, ((Int(previous) ?? 0) > 1 || pluralNumbers.contains(previous.lowercased())),
           !old.isEmpty, new == old + "s" || new == old + "es" {
            return example(.plural, subject: previous)
        }
        let lesson: Lesson
        switch (old, new) {
        case ("a", "an"), ("an", "a"): lesson = .article
        case ("their", "they're"), ("there", "they're"), ("they're", "their"),
             ("they're", "there"), ("their", "there"), ("there", "their"): lesson = .theyre
        case ("your", "you're"), ("you're", "your"): lesson = .youre
        case ("its", "it's"), ("it's", "its"): lesson = .its
        case _ where !old.contains("'") && new.contains("'") && old == new.replacingOccurrences(of: "'", with: ""):
            lesson = .contraction
        default: lesson = .other
        }
        return example(lesson)
    }

    private static let subjects: Set<String> = ["i", "you", "he", "she", "it", "we", "they"]
    private static let pluralNumbers: Set<String> = ["two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
    private static let verbForms: [Set<String>] = [
        ["am", "is", "are"], ["was", "were"], ["have", "has"], ["do", "does"], ["don't", "doesn't"],
    ]
    private static let frenchSubjects: Set<String> = ["je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles"]
    private static let frenchVerbForms: [Set<String>] = [
        ["peux", "peut", "pouvons", "pouvez", "peuvent"], ["suis", "es", "est", "sommes", "êtes", "sont"],
        ["ai", "as", "a", "avons", "avez", "ont"], ["veux", "veut", "voulons", "voulez", "veulent"],
    ]
}
