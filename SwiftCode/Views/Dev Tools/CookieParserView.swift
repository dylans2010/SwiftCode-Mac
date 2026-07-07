import SwiftUI

struct CookieParserView: View {
    @State private var rawCookies = "session_id=abc123; user_id=456; theme=dark"
    @State private var cookies: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $rawCookies)
                .font(.system(.body, design: .monospaced))
                .padding()

            Button("Parse Cookies") { parse() }
                .buttonStyle(.borderedProminent)
                .padding()

            List {
                ForEach(cookies.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).fontWeight(.bold)
                        Spacer()
                        Text(cookies[key] ?? "").foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Cookie Parser")
    }

    func parse() {
        var dict: [String: String] = [:]
        let parts = rawCookies.components(separatedBy: ";")
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 {
                dict[pair[0]] = pair[1]
            }
        }
        cookies = dict
    }
}
