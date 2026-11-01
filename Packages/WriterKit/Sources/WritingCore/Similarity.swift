import Foundation

/// String similarity helpers. eval/bench.py implements the same functions so that
/// guard decisions in the benchmark match the app exactly.
public enum Similarity {
    /// Optimal string alignment distance: Levenshtein plus adjacent transpositions.
    public static func osaDistance<T: Equatable>(_ a: [T], _ b: [T]) -> Int {
        let n = a.count, m = b.count
        if n == 0 || m == 0 { return max(n, m) }
        var prev2 = [Int](repeating: 0, count: m + 1)
        var prev = Array(0...m)
        var cur = [Int](repeating: 0, count: m + 1)
        for i in 1...n {
            cur[0] = i
            for j in 1...m {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    cur[j] = min(cur[j], prev2[j - 2] + 1)
                }
            }
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return prev[m]
    }

    /// 1 - distance / longer length, case-insensitive, over Unicode scalars
    /// (Python code points). Very long inputs are compared word by word to stay cheap.
    public static func ratio(_ a: String, _ b: String) -> Double {
        let la = Array(a.lowercased().unicodeScalars), lb = Array(b.lowercased().unicodeScalars)
        if la.isEmpty && lb.isEmpty { return 1 }
        if la.count * lb.count > 4_000_000 {
            let wa = words(a), wb = words(b)
            if wa.isEmpty && wb.isEmpty { return 1 }
            return 1 - Double(osaDistance(wa, wb)) / Double(max(wa.count, wb.count))
        }
        return 1 - Double(osaDistance(la, lb)) / Double(max(la.count, lb.count))
    }

    /// Lowercased letter/digit runs with apostrophes removed ("I'm" -> "im").
    public static func words(_ s: String) -> [String] {
        let cleaned = s.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
        var result: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in cleaned.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                result.append(String(current))
                current = String.UnicodeScalarView()
            }
        }
        if !current.isEmpty { result.append(String(current)) }
        return result
    }

    /// Output words (4+ letters) that are neither in the source (exactly or as a typo fix)
    /// nor plausibly new, because they come from the prompt's own examples.
    public static func leakedWords(source: String, output: String, exampleWords: Set<String>) -> [String] {
        if exampleWords.isEmpty { return [] }
        let sourceWords = Set(words(source))
        let sourceForms = Set(sourceWords.map(agreementForm))
        let src = sourceWords.map { Array(foldedWord($0).unicodeScalars) }
        var leaked: [String] = []
        for word in Set(words(output)) where word.count >= 4 && exampleWords.contains(word) {
            if sourceForms.contains(agreementForm(word)) { continue }
            let w = Array(foldedWord(word).unicodeScalars)
            let known = src.contains { 1 - Double(osaDistance(w, $0)) / Double(max(w.count, $0.count)) >= 0.6 }
            if !known { leaked.append(word) }
        }
        return leaked.sorted()
    }

    /// Fraction of the source's words (3+ letters) that survive in the output,
    /// allowing for agreement changes and typo fixes (fuzzy match >= 0.6). A correction keeps most words;
    /// an answer to the text does not.
    public static func wordRetention(source: String, output: String) -> Double {
        let src = Set(words(source).filter { $0.count >= 3 })
        if src.isEmpty { return 1 }
        let out = Set(words(output))
        let outputForms = Set(out.map(agreementForm))
        let outScalars = out.map { Array(foldedWord($0).unicodeScalars) }
        var kept = 0
        for word in src {
            if outputForms.contains(agreementForm(word)) { kept += 1; continue }
            let w = Array(foldedWord(word).unicodeScalars)
            if outScalars.contains(where: { 1 - Double(osaDistance(w, $0)) / Double(max(w.count, $0.count)) >= 0.6 }) {
                kept += 1
            }
        }
        return Double(kept) / Double(src.count)
    }

    private static func foldedWord(_ word: String) -> String {
        word.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }

    // Subject agreement can change most letters in a short verb while preserving its meaning and tense.
    private static func agreementForm(_ word: String) -> String {
        switch word {
        case "am", "is", "are": return "be"
        case "was", "were": return "was"
        case "has", "have": return "have"
        case "do", "does": return "do"
        default: return word
        }
    }
}
