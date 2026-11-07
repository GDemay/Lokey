/// Limits automatic replacements to one missing letter or one nearby AZERTY key.
public enum AzertyWordCorrection {
    public static func uniqueMatch(for word: String, guesses: [String]) -> String? {
        let typed = Array(word.lowercased())
        var matches: Set<String> = []
        for guess in guesses {
            let replacement = guess.lowercased()
            let letters = Array(replacement)
            guard letters.allSatisfy(\.isLetter), isLikelyTypo(typed, letters) else { continue }
            matches.insert(replacement)
            if matches.count > 1 { return nil }
        }
        guard let match = matches.first else { return nil }
        return word.first?.isUppercase == true ? match.prefix(1).uppercased() + match.dropFirst() : match
    }

    private static func isLikelyTypo(_ typed: [Character], _ guess: [Character]) -> Bool {
        if guess.count == typed.count + 1 {
            let missing = zip(typed, guess).prefix(while: { $0 == $1 }).count
            return typed[missing...].elementsEqual(guess.dropFirst(missing + 1))
        }
        guard guess.count == typed.count else { return false }
        let differences = zip(typed, guess).filter { $0 != $1 }
        guard differences.count == 1, let (pressed, intended) = differences.first,
              let from = positions[pressed], let to = positions[intended] else { return false }
        return abs(from.row - to.row) <= 1 && abs(from.column - to.column) <= 1
    }

    private static let positions: [Character: (row: Int, column: Double)] = {
        var positions: [Character: (row: Int, column: Double)] = [:]
        for (row, keys) in KeyboardLayout.azerty.letterRows.enumerated() {
            let offset = Double(10 - keys.count) / 2
            for (column, key) in keys.enumerated() where key.isLetter {
                positions[key] = (row, Double(column) + offset)
            }
        }
        return positions
    }()
}
