import SwiftUI

struct OptimizationRule: Identifiable {
    let id = UUID()
    let category: String
    let topic: String
    let command: String
    let explanation: String
}

public struct AppleSiliconOptimizationCheatsheetView: View {
    private let rules = [
        OptimizationRule(
            category: "Architecture",
            topic: "Native arm64 Compilation",
            command: "ARCHS = arm64",
            explanation: "Ensure targets compile natively for Apple Silicon without relying on the Rosetta 2 translation layer."
        ),
        OptimizationRule(
            category: "Vectorization",
            topic: "Accelerate Framework SIMD",
            command: "vDSP_vadd(vectorA, 1, vectorB, 1, &result, 1, length)",
            explanation: "Leverage high-performance hardware vector operations in Apple's Neon units rather than manual loops."
        ),
        OptimizationRule(
            category: "Graphics",
            topic: "Metal Command Encoding",
            command: "MTLCreateSystemDefaultDevice()",
            explanation: "Instantiate state-level graphics pipelines directly on unified memory architectures for high bandwidth and low latencies."
        )
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Apple Silicon Optimization Reference")
                        .font(.title.bold())
                    Text("Leverage native ARM64 registers, unified memory caches, and custom neural core capabilities.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach(rules) { rule in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text(rule.category.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)

                                Text(rule.topic)
                                    .font(.headline)
                                Spacer()
                            }

                            Text(rule.explanation)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(rule.command)
                                .font(.system(.body, design: .monospaced))
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.2))
                                .cornerRadius(6)
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
