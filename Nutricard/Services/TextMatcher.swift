import Foundation

/// Word-based phrase matching ("rice brown" matches "Rice, brown, cooked" but "salted" does not match "unsalted").
enum TextMatcher {
    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .folding(options: .diacriticInsensitive, locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    static func contains(_ haystack: [String], phrase: [String]) -> Bool {
        guard !phrase.isEmpty, phrase.count <= haystack.count else { return false }
        for start in 0...(haystack.count - phrase.count)
        where Array(haystack[start..<(start + phrase.count)]) == phrase {
            return true
        }
        return false
    }

    /// Score of the best (longest) matching phrase, or nil when nothing matches or an exclusion is present.
    static func score(text: String, phrases: [String], excluding: [String] = []) -> Int? {
        let words = tokens(text)
        if excluding.contains(where: { contains(words, phrase: tokens($0)) }) { return nil }
        let matched = phrases
            .map(tokens)
            .filter { contains(words, phrase: $0) }
            .map { $0.joined(separator: " ").count }
        return matched.max()
    }
}
