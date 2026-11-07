import SwiftUI

struct TextLineRemoverView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var removeEmpty = true
    @State private var removeDuplicates = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("Remove Empty Lines", isOn: $removeEmpty)
                Toggle("Remove Duplicate Lines", isOn: $removeDuplicates)
                Spacer()
                Button("Process Text") { process() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            HSplitView {
                TextEditor(text: $input)
                TextEditor(text: .constant(output))
            }
        }
        .navigationTitle("Text Line Remover")
    }

    func process() {
        var lines = input.components(separatedBy: .newlines)
        if removeEmpty {
            lines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        if removeDuplicates {
            var seen = Set<String>()
            lines = lines.filter { seen.insert($0).inserted }
        }
        output = lines.joined(separator: "\n")
    }
}
