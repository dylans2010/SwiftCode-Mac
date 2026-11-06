// Ported from SwiftCode-Legacy (Dylan's own code, MIT-authorised direct port).
// Rebuilt in Ycode style: default accent, no Legacy liquid-glass/orange styling.

import SwiftUI

struct TextDeduplicatorView: View {
    @State private var input = ""
    @State private var output = ""
    @State private var separator = " "

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Separator:")
                TextField("Space", text: $separator)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Spacer()
                Button("Deduplicate") { process() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            

            HSplitView {
                TextEditor(text: $input)
                TextEditor(text: .constant(output))
            }
        }
        .navigationTitle("Text Deduplicator")
    }

    func process() {
        let sep = separator == " " ? " " : (separator.isEmpty ? " " : separator)
        let words = input.components(separatedBy: sep)
        var seen = Set<String>()
        let unique = words.filter { seen.insert($0).inserted }
        output = unique.joined(separator: sep)
    }
}
