import SwiftUI

struct CodeIntelligenceView: View {
    @StateObject private var engine = CodeIntelligenceEngine.shared
    @Environment(ProjectSessionStore.self) private var sessionStore

    var body: some View {
        AdvancedToolScreen(title: "Code Intelligence") {
            AdvancedToolCard(title: "Realtime Index") {
                HStack {
                    Button("Refresh Intelligence") {
                        engine.index(content: sessionStore.activeFileContent)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    MetricPill(label: "Suggestions", value: "\(engine.completions.count)")
                        .frame(maxWidth: 180)
                }
            }

            AdvancedToolCard(title: "Autocomplete Suggestions") {
                ForEach(engine.completions, id: \.self) { Text("• \($0)") }
            }

            AdvancedToolCard(title: "Detected Symbols") {
                ForEach(engine.symbols, id: \.self) { symbol in
                    VStack(alignment: .leading) {
                        Text(symbol).font(.callout.monospaced())
                        Text(engine.quickDoc(for: symbol)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
