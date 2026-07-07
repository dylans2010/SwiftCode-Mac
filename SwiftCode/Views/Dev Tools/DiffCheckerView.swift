import SwiftUI

struct DiffCheckerView: View {
    @State private var text1 = "Apple\nBanana\nCherry"
    @State private var text2 = "Apple\nBlueberry\nCherry"
    @State private var diffResults = "Changes will appear here"

    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Original Text")
                        .font(.headline)
                    TextEditor(text: $text1)
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }

                VStack(alignment: .leading) {
                    Text("Changed Text")
                        .font(.headline)
                    TextEditor(text: $text2)
                        .font(.system(.body, design: .monospaced))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }

            Button("Check Diff") { checkDiff() }
                .buttonStyle(.borderedProminent)

            VStack(alignment: .leading) {
                Text("Difference")
                    .font(.headline)
                ScrollView {
                    Text(diffResults)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .frame(height: 200)
        }
        .padding()
        .navigationTitle("Diff Checker")
    }

    func checkDiff() {
        let lines1 = text1.components(separatedBy: .newlines)
        let lines2 = text2.components(separatedBy: .newlines)

        var results = ""
        let maxLines = max(lines1.count, lines2.count)

        for i in 0..<maxLines {
            let l1 = i < lines1.count ? lines1[i] : ""
            let l2 = i < lines2.count ? lines2[i] : ""

            if l1 == l2 {
                results += "  \(l1)\n"
            } else {
                if !l1.isEmpty { results += "- \(l1)\n" }
                if !l2.isEmpty { results += "+ \(l2)\n" }
            }
        }

        diffResults = results
    }
}
