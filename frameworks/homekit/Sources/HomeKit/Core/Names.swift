import Foundation

public enum SwiftCodeNameRules {
    static let allowedLast: Set<Character> = [".", ")", "]", "'", "\"", "!", "?", "\u{2019}"]

    public static func validate(_ name: String) -> Result<String, HMError> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return .failure(HMError(.nameDoesNotStartWithValidCharacters)) }
        for scalar in trimmed.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar)
                || scalar.properties.generalCategory == .format {
                return .failure(HMError(.nameContainsProhibitedCharacters))
            }
        }
        if !(first.isLetter || first.isNumber) { return .failure(HMError(.nameDoesNotStartWithValidCharacters)) }
        let last = trimmed.last!
        if !(last.isLetter || last.isNumber || allowedLast.contains(last)) {
            return .failure(HMError(.nameDoesNotEndWithValidCharacters))
        }
        return .success(trimmed)
    }

    public static func key(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func similar(_ a: String, _ b: String) -> Bool { key(a) == key(b) }
}
