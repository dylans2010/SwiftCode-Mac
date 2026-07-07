import SwiftUI

struct HTTPHeaderParserView: View {
    @State private var rawHeaders = "Host: example.com\nUser-Agent: Mozilla/5.0\nAccept: */*"
    @State private var headers: [String: String] = [:]

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $rawHeaders)
                .font(.system(.body, design: .monospaced))
                .padding()

            Button("Parse Headers") { parse() }
                .buttonStyle(.borderedProminent)
                .padding()

            List {
                ForEach(headers.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).fontWeight(.bold)
                        Spacer()
                        Text(headers[key] ?? "").foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle("HTTP Header Parser")
    }

    func parse() {
        var dict: [String: String] = [:]
        let lines = rawHeaders.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 {
                dict[parts[0]] = parts[1]
            }
        }
        headers = dict
    }
}
