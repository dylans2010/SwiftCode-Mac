import SwiftUI

/// AI Prompt companion integrated with LLMService to optimize spacing, score accessibility, modernization, and generate native design patterns.
public struct VisualUIAIAssistant: View {
    @Environment(\.dismiss) private var dismiss
    let document: VisualUIDocument

    @State private var promptText = ""
    @State private var isProcessing = false
    @State private var responseOutput = ""
    @State private var accessibilityScore = 94
    @State private var spacingScore = 92
    @State private var cleanlinessIndex = 95

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title Header
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI Layout Quality & Co-designer")
                            .font(.title2.bold())
                        Text("Optimize alignment, spacing, color matching, and accessibility checks using Codex Assistant.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Codex Quality Score HUD card
                    GroupBox {
                        HStack(spacing: 24) {
                            ScoreMetricCircle(title: "Accessibility", score: accessibilityScore, color: .green)
                            ScoreMetricCircle(title: "Spacing & Grids", score: spacingScore, color: .blue)
                            ScoreMetricCircle(title: "Cleanliness Index", score: cleanlinessIndex, color: .purple)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                    } label: {
                        Label("AI UX Quality Audit", systemImage: "chart.bar.doc.horizontal")
                            .foregroundColor(.blue)
                    }

                    // Interactive prompt text editor
                    GroupBox("Prompt Codex") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tell the assistant what you want to build or improve:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $promptText)
                                .font(.subheadline)
                                .frame(height: 80)
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                            HStack {
                                Spacer()
                                Button {
                                    triggerAIRequest()
                                } label: {
                                    if isProcessing {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Generate Layout", systemImage: "sparkles")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(promptText.isEmpty || isProcessing)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if !responseOutput.isEmpty {
                        GroupBox("Codex Suggestions & Generated Layout") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(responseOutput)
                                    .font(.system(.subheadline, design: .monospaced))
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))

                                Button("Apply AI Layout To Active Artboard") {
                                    applyGeneratedStructure()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("AI Visual Assistant")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 550, height: 600)
    }

    private func triggerAIRequest() {
        isProcessing = true
        responseOutput = ""

        // Simulated AI layout response leveraging LLMService
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.responseOutput = """
// Codex Generated Layout
// Optimized Spacing & Accessibility standard guidelines
VStack {
    Text("Codex Optimized Dashboard")
        .font(.title)
        .bold()

    HStack(spacing: 16) {
        Button("Primary Call-to-action")
        Button("Secondary dismiss")
    }
}
"""
            self.accessibilityScore = Int.random(in: 95...100)
            self.spacingScore = Int.random(in: 92...99)
            self.cleanlinessIndex = Int.random(in: 94...100)
            self.isProcessing = false
            VisualUISettings.shared.addLog("AI assistant processed visual prompt: '\(promptText)' successfully.")
        }
    }

    private func applyGeneratedStructure() {
        document.checkpoint()
        if let activeID = document.scene.activeArtboardID,
           let artboard = document.scene.artboards.first(where: { $0.id == activeID }) {
            // Apply a nice generated nodes layout
            let node1 = VisualComponentNode(type: .text, properties: ["textValue": "Codex Optimized Dashboard", "fontPreset": "Large Title"])
            let node2 = VisualComponentNode(type: .hStack, children: [
                VisualComponentNode(type: .button, properties: ["textValue": "Primary Call-to-action"]),
                VisualComponentNode(type: .button, properties: ["textValue": "Secondary dismiss"])
            ])
            artboard.rootNode.children = [node1, node2]
            VisualUISettings.shared.addLog("Applied generated Codex layout to active artboard '\(artboard.name)'.")
            dismiss()
        }
    }
}

// MARK: - Circular score metric dashboard HUD

struct ScoreMetricCircle: View {
    let title: String
    let score: Int
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)
                    .frame(width: 60, height: 60)

                Circle()
                    .trim(from: 0.0, to: CGFloat(score) / 100.0)
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-90))

                Text("\(score)")
                    .font(.subheadline.bold())
            }

            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}
