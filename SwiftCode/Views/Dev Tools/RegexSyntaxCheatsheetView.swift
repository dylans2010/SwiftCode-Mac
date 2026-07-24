import SwiftUI

struct RegexToken: Identifiable {
    let id = UUID()
    let pattern: String
    let meaning: String
    let example: String
}

public struct RegexSyntaxCheatsheetView: View {
    private let tokens = [
        RegexToken(pattern: "^", meaning: "Start of string", example: "^Hello matches 'Hello' only at start"),
        RegexToken(pattern: "$", meaning: "End of string", example: "World$ matches 'World' only at end"),
        RegexToken(pattern: ".", meaning: "Any single character except newline", example: "c.t matches 'cat', 'cot', 'c1t'"),
        RegexToken(pattern: "\\d", meaning: "Any digit [0-9]", example: "\\d{3} matches '123', '904'"),
        RegexToken(pattern: "\\D", meaning: "Any non-digit character", example: "\\D matches 'A', '@'"),
        RegexToken(pattern: "\\w", meaning: "Alphanumeric word character [a-zA-Z0-9_]", example: "\\w+ matches 'user_123'"),
        RegexToken(pattern: "\\s", meaning: "Whitespace character", example: "\\s matches tabs, spaces, newlines"),
        RegexToken(pattern: "*", meaning: "Zero or more times", example: "ab* matches 'a', 'ab', 'abbbb'"),
        RegexToken(pattern: "+", meaning: "One or more times", example: "ab+ matches 'ab', 'abbb' but not 'a'"),
        RegexToken(pattern: "?", meaning: "Zero or one time (Optional)", example: "colors? matches 'color' or 'colors'"),
        RegexToken(pattern: "{n,m}", meaning: "Between n and m repetitions", example: "\\d{2,4} matches years like '99', '2024'"),
        RegexToken(pattern: "[abc]", meaning: "Any character in set", example: "[cr]at matches 'cat' or 'rat'")
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Regex Syntax Cheat Sheet", systemImage: "text.magnifyingglass")
                    .font(.title2.bold())
                Text("Quick reference guide for regular expressions (Regex) syntax, token classes, and quantifiers.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial)

            Divider()

            List {
                ForEach(tokens) { token in
                    HStack(spacing: 16) {
                        Text(token.pattern)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                            .frame(width: 100, alignment: .leading)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(token.meaning)
                                .font(.headline)
                            Text("Example: \(token.example)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.inset)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
