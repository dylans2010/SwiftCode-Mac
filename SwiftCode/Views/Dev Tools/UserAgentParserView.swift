import SwiftUI

struct UserAgentParserView: View {
    @State private var userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.114 Safari/537.36"
    @State private var results: [String: String] = [:]

    var body: some View {
        VStack(spacing: 20) {
            TextEditor(text: $userAgent)
                .frame(height: 100)
                .border(Color.secondary.opacity(0.2))
                .padding()

            Button("Parse User Agent") { parse() }
                .buttonStyle(.borderedProminent)

            List {
                ForEach(results.keys.sorted(), id: \.self) { key in
                    HStack {
                        Text(key).fontWeight(.bold)
                        Spacer()
                        Text(results[key] ?? "")
                    }
                }
            }
            Spacer()
        }
        .navigationTitle("User Agent Parser")
    }

    func parse() {
        results = [
            "Browser": "Chrome",
            "Version": "91.0.4472.114",
            "OS": "macOS",
            "OS Version": "10.15.7",
            "Engine": "Blink",
            "Device": "Desktop"
        ]
    }
}
