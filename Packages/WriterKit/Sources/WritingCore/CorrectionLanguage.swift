import Foundation

public enum CorrectionLanguage: String, Sendable {
    case english, french

    // Function words distinguish a sentence's language without loading another model in the extension.
    public static func detect(in text: String) -> CorrectionLanguage {
        let words = Set(Similarity.words(text))
        let french: Set<String> = ["je", "jai", "jétais", "tu", "il", "elle", "nous", "vous", "ils", "elles", "les", "des", "une", "dans", "pour", "avec", "pas", "est", "suis", "sont", "bonjour", "merci", "français", "francais", "ça", "cest", "était", "demain", "hier", "peux", "peut", "veux"]
        let english: Set<String> = ["i", "im", "you", "he", "she", "we", "they", "the", "this", "that", "is", "are", "have", "has", "dont", "doesnt", "will", "would", "what", "how", "please", "thanks", "your", "my", "its", "their"]
        let frenchScore = words.intersection(french).count * 3 + words.intersection(["le", "la", "de", "du", "se", "ne", "au"]).count
        let englishScore = words.intersection(english).count * 3
        return frenchScore >= 3 && frenchScore > englishScore ? .french : .english
    }
}
