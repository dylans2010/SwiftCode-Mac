import SwiftUI

struct PerformanceTip: Identifiable {
    let id = UUID()
    let title: String
    let badCode: String
    let goodCode: String
    let rationale: String
}

public struct SwiftUIPerformanceCheatsheetView: View {
    private let tips = [
        PerformanceTip(
            title: "Dynamic Views & Lazy Containers",
            badCode: "ScrollView {\n    VStack {\n        ForEach(0..<10000) { i in\n            RowView(index: i)\n        }\n    }\n}",
            goodCode: "ScrollView {\n    LazyVStack {\n        ForEach(0..<10000) { i in\n            RowView(index: i)\n        }\n    }\n}",
            rationale: "VStack instantiates all of its child row views immediately upon allocation. LazyVStack deferrow initialization until cells enter the viewport safe-bounds."
        ),
        PerformanceTip(
            title: "Isolating State & Body Updates",
            badCode: "struct ParentView: View {\n    @State private var text = \"\"\n    var body: some View {\n        VStack {\n            TextField(\"Input\", text: $text)\n            HugeExpensiveStaticView()\n        }\n    }\n}",
            goodCode: "struct InputSubView: View {\n    @Binding var text: String\n    var body: some View {\n        TextField(\"Input\", text: $text)\n    }\n}",
            rationale: "When `@State` changes, the entire view structure's body property re-evaluates. Splitting transient inputs into subviews isolates the invalidation scope."
        ),
        PerformanceTip(
            title: "Identity vs. Structural Changes",
            badCode: "if showDetail {\n    DetailView()\n} else {\n    EmptyView()\n}",
            goodCode: "DetailView()\n    .opacity(showDetail ? 1 : 0)",
            rationale: "Using if-else branches alters structural identity, forcing SwiftUI to destroy and re-create view hierarchies. Modifier opacity transitions keep identities persistent."
        )
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SwiftUI Performance Cookbook")
                        .font(.title.bold())
                    Text("Avoid viewport stutters and unnecessary body evaluations using optimized structural patterns.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(tips) { tip in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(tip.title)
                                .font(.headline)
                                .foregroundColor(.orange)

                            HStack(alignment: .top, spacing: 16) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("🛑 AVOID")
                                        .font(.caption.bold())
                                        .foregroundColor(.red)
                                    Text(tip.badCode)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.red.opacity(0.08))
                                        .cornerRadius(6)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    Text("🟢 PREFER")
                                        .font(.caption.bold())
                                        .foregroundColor(.green)
                                    Text(tip.goodCode)
                                        .font(.system(.caption, design: .monospaced))
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.green.opacity(0.08))
                                        .cornerRadius(6)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("RATIONALE")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.secondary)
                                Text(tip.rationale)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(10)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }
            }
            .padding(24)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
