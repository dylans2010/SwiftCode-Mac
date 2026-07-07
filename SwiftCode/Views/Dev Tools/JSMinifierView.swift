import SwiftUI

struct JSMinifierView: View {
    @State private var input = "function hello() {\n  console.log(\"Hello World\");\n}"
    @State private var output = ""

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Spacer()
                Button("Minify JS") { minify() }
                    .buttonStyle(.borderedProminent)
            }
            .padding([.top, .horizontal])

            VStack(alignment: .leading) {
                Text("Source Code")
                    .font(.headline)
                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 200)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding(.horizontal)

            VStack(alignment: .leading) {
                Text("Minified Output")
                    .font(.headline)
                TextEditor(text: .constant(output))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 100)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
            }
            .padding([.bottom, .horizontal])
        }
        .navigationTitle("JS Minifier")
        .onAppear { minify() }
    }

    func minify() {
        // Simple mock minifier: remove extra whitespace and newlines
        output = input
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
