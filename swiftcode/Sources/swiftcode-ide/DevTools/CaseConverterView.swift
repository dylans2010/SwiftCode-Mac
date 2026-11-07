import SwiftUI

struct CaseConverterView: View {
    @State private var input = ""
    @State private var results: [(String, String)] = []

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("Input Text")
                    .font(.headline)
                TextField("Type something...", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: input) { convert() }
            }
            .padding([.top, .horizontal])

            List(results, id: \.0) { name, value in
                HStack {
                    VStack(alignment: .leading) {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(value)
                            .font(.system(.body, design: .monospaced))
                    }
                    Spacer()
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(value, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Case Converter")
    }

    func convert() {
        guard !input.isEmpty else {
            results = []
            return
        }

        results = [
            ("LOWERCASE", input.lowercased()),
            ("UPPERCASE", input.uppercased()),
            ("CamelCase", toCamelCase(input)),
            ("snake_case", toSnakeCase(input)),
            ("kebab-case", toKebabCase(input)),
            ("PascalCase", toPascalCase(input))
        ]
    }

    func toCamelCase(_ str: String) -> String {
        let words = str.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        guard let first = words.first?.lowercased() else { return "" }
        let rest = words.dropFirst().map { $0.capitalized }
        return ([first] + rest).joined()
    }

    func toSnakeCase(_ str: String) -> String {
        str.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.map { $0.lowercased() }.joined(separator: "_")
    }

    func toKebabCase(_ str: String) -> String {
        str.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.map { $0.lowercased() }.joined(separator: "-")
    }

    func toPascalCase(_ str: String) -> String {
        str.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.map { $0.capitalized }.joined()
    }
}
