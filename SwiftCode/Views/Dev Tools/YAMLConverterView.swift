import SwiftUI

struct YAMLConverterView: View {
    @State private var jsonInput = "{\n  \"name\": \"John Doe\",\n  \"age\": 30,\n  \"city\": \"New York\"\n}"
    @State private var yamlOutput = "name: John Doe\nage: 30\ncity: New York"

    var body: some View {
        VStack(spacing: 20) {
            Text("Convert JSON to YAML")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("JSON")
                        .font(.caption)
                    TextEditor(text: $jsonInput)
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading) {
                    Text("YAML")
                        .font(.caption)
                    TextEditor(text: .constant(yamlOutput))
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            Button("Convert") { convert() }
                .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .navigationTitle("YAML Converter")
    }

    func convert() {
        // Simple mock JSON to YAML converter
        if jsonInput.contains("name") {
            yamlOutput = "name: John Doe\nage: 30\ncity: New York"
        } else {
            yamlOutput = "# Resulting YAML will appear here"
        }
    }
}
