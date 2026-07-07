import SwiftUI

struct StringEscaperView: View {
    @State private var input = "Hello \"World\"\nLine 2"
    @State private var output = ""
    @State private var mode = 0 // 0: Escape, 1: Unescape

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $mode) {
                Text("Escape").tag(0)
                Text("Unescape").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            HSplitView {
                TextEditor(text: $input)
                    .font(.system(.body, design: .monospaced))
                VStack {
                    HStack {
                        Spacer()
                        Button("Process") { process() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.bottom, 5)
                    TextEditor(text: .constant(output))
                        .font(.system(.body, design: .monospaced))
                }
                .padding()
            }
        }
        .navigationTitle("String Escaper")
    }

    func process() {
        if mode == 0 {
            output = input
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t")
                .replacingOccurrences(of: "\r", with: "\\r")
        } else {
            output = input
                .replacingOccurrences(of: "\\n", with: "\n")
                .replacingOccurrences(of: "\\t", with: "\t")
                .replacingOccurrences(of: "\\r", with: "\r")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
    }
}
