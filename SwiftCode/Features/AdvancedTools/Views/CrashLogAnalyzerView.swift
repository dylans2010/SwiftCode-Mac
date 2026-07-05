import SwiftUI

struct CrashLogAnalyzerView: View {
    @State private var crashLog = ""

    private var parsed: CrashAnalysis { CrashAnalysis.parse(log: crashLog) }

    var body: some View {
        AdvancedToolScreen(title: "Crash Log Analyzer") {
            AdvancedToolCard(title: "Crash Input") {
                TextField("Paste crash log", text: $crashLog, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            AdvancedToolCard(title: "Failing Function") { Text(parsed.failingFunction) }
            AdvancedToolCard(title: "Likely Cause") { Text(parsed.likelyCause) }
            AdvancedToolCard(title: "Relevant Locations") { Text(parsed.fileHints.joined(separator: "\n")) }
        }
    }
}

private struct CrashAnalysis {
    let failingFunction: String
    let likelyCause: String
    let fileHints: [String]

    static func parse(log: String) -> Self {
        let lines = log.split(separator: "\n").map(String.init)
        let frame = lines.first(where: { $0.contains(" 0 ") || $0.localizedCaseInsensitiveContains("fatal error") || $0.localizedCaseInsensitiveContains("terminating app") }) ?? "Unknown function"
        let reason = lines.first(where: { $0.localizedCaseInsensitiveContains("reason:") || $0.localizedCaseInsensitiveContains("fatal error") }) ?? "Cause not found in log."
        let fileRefs = lines.filter { $0.contains(".swift") }.prefix(8)

        return .init(failingFunction: frame, likelyCause: reason, fileHints: Array(fileRefs))
    }
}
