import SwiftUI

struct YAMLToJSONView: View {
    @State private var yamlInput = "name: John\nage: 30\nskills:\n  - Swift\n  - Kotlin"
    @State private var jsonOutput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Convert YAML to JSON") { convert() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $yamlInput)
                    .font(.system(.body, design: .monospaced))
                TextEditor(text: .constant(jsonOutput))
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("YAML to JSON")
    }

    func convert() {
        jsonOutput = "YAML to JSON conversion interface. This would typically use a library like Yams for robust parsing."
    }
}
