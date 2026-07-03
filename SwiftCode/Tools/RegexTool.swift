import Foundation

public enum RegexTool {
    public static func firstMatch(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsString = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        guard let result = results.first else { return [] }

        var matches: [String] = []
        for i in 0..<result.numberOfRanges {
            matches.append(nsString.substring(with: result.range(at: i)))
        }
        return matches
    }
}
