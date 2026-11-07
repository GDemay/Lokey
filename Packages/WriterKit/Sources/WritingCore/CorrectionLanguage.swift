import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

public enum CorrectionLanguage: String, Sendable {
    case english, french

    // Function words distinguish a sentence's language without loading another model in the extension.
    public static func detect(in text: String) -> CorrectionLanguage {
        let (english, french) = scores(in: text)
        return french >= 3 && french > english ? .french : .english
    }

    static func historyLanguage(in text: String) -> String? {
        #if canImport(NaturalLanguage)
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        if let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
           confidence >= 0.65 {
            return language.rawValue
        }
        #endif
        let (english, french) = scores(in: text)
        if french >= 3 && french > english { return "fr" }
        if english > french { return "en" }
        return nil
    }

    private static func scores(in text: String) -> (english: Int, french: Int) {
        let words = Set(Similarity.words(text))
        let french: Set<String> = ["je", "jai", "jétais", "tu", "il", "elle", "nous", "vous", "ils", "elles", "les", "des", "une", "dans", "pour", "avec", "comme", "pas", "est", "suis", "sont", "bonjour", "merci", "français", "francais", "ça", "cest", "sest", "était", "demain", "hier", "peux", "peut", "veux", "mdr"]
        let english: Set<String> = ["i", "im", "you", "he", "she", "we", "they", "the", "this", "that", "is", "are", "have", "has", "dont", "doesnt", "will", "would", "what", "how", "please", "thanks", "your", "my", "its", "their"]
        let frenchScore = words.intersection(french).count * 3 + words.intersection(["le", "la", "de", "du", "se", "ne", "au"]).count
        let englishScore = words.intersection(english).count * 3
        return (englishScore, frenchScore)
    }
}
