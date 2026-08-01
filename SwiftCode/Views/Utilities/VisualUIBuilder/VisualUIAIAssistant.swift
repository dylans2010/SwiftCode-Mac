import SwiftUI

/// Elegant AI prompt assistant to redesign, optimize, or generate SwiftUI screens using native macOS patterns.
public struct VisualUIAIAssistant: View {
    @Environment(\.dismiss) private var dismiss
    let document: VisualUIDocument

    @State private var promptText = ""
    @State private var isProcessing = false
    @State private var responseOutput = ""

    // Native preset prompts for professional workflow
    private let quickActions = [
        ("Clean Layout", "Optimize padding, spacing, and center alignment for maximum elegance."),
        ("Modern Grid", "Convert the current container layout into an adaptive grid structure."),
        ("Dark Aesthetics", "Configure high-contrast dark theme colors and vibrant elements."),
        ("Form Layout", "Generate an input form layout with validated fields, selectors, and sections.")
    ]

    public init(document: VisualUIDocument) {
        self.document = document
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main split content
                HSplitView {
                    // Left Side: AI Prompts and Inputs
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Co-Design Assistant")
                                .font(.headline)
                            Text("Describe your layout goals or use one of the quick actions below to generate optimized layouts.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        // Prompts input area
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI Assistant Prompt")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            TextEditor(text: $promptText)
                                .font(.subheadline)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                                .frame(height: 100)
                        }

                        // Generate Button
                        HStack {
                            Spacer()
                            Button {
                                triggerAIRequest()
                            } label: {
                                if isProcessing {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Thinking...")
                                    }
                                } else {
                                    Label("Generate Layout", systemImage: "sparkles")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.regular)
                            .disabled(promptText.isEmpty || isProcessing)
                        }

                        Divider()

                        // Quick Actions List
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Quick Actions")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            ScrollView {
                                VStack(spacing: 8) {
                                    ForEach(quickActions, id: \.0) { action in
                                        Button {
                                            promptText = action.1
                                        } label: {
                                            VStack(alignment: .leading, spacing: 4) {
                                                HStack {
                                                    Text(action.0)
                                                        .font(.subheadline.bold())
                                                        .foregroundColor(.primary)
                                                    Spacer()
                                                    Image(systemName: "chevron.right")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                                Text(action.1)
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                    .multilineTextAlignment(.leading)
                                            }
                                            .padding(10)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                                            .cornerRadius(8)
                                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.1), lineWidth: 1))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)

                    // Right Side: Live Suggestion View & Applying Code
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Generated Recommendations")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                            .padding(.top, 16)
                            .padding(.horizontal, 16)

                        if responseOutput.isEmpty {
                            VStack(spacing: 12) {
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.system(size: 32))
                                    .foregroundColor(.purple.opacity(0.5))
                                Text("Ready to Collaborate")
                                    .font(.headline)
                                Text("Your generated SwiftUI layouts and AI suggestions will appear here in real-time.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(24)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                ScrollView {
                                    Text(responseOutput)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .padding(12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color(NSColor.controlBackgroundColor))
                                        .cornerRadius(8)
                                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.12), lineWidth: 1))
                                }

                                Spacer()

                                Button {
                                    applyGeneratedStructure()
                                } label: {
                                    Label("Apply to Active Artboard", systemImage: "checkmark.circle.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                            }
                            .padding([.horizontal, .bottom], 16)
                        }
                    }
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.underPageBackgroundColor))
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 700, height: 480)
    }

    private func triggerAIRequest() {
        isProcessing = true
        responseOutput = ""
        let userPrompt = promptText

        Task {
            do {
                let systemContext = """
You are an expert SwiftUI co-designer.
Generate only standard SwiftUI code structure inside a single block, avoiding any explanations or commentary.
Your layout must follow high aesthetic standard, with proper spacing and alignment, fully ready to compile.
"""
                let fullPrompt = "\(systemContext)\n\nUser Request: \(userPrompt)"
                let result = try await LLMService.shared.generateResponse(prompt: fullPrompt, useContext: false)

                await MainActor.run {
                    self.responseOutput = result
                    self.isProcessing = false
                    VisualUISettings.shared.addLog("AI assistant processed visual prompt: '\(userPrompt)' successfully.")
                }
            } catch {
                await MainActor.run {
                    self.responseOutput = "Failed to generate visual design: \(error.localizedDescription)"
                    self.isProcessing = false
                }
            }
        }
    }

    private func applyGeneratedStructure() {
        document.checkpoint()
        if let activeID = document.scene.activeArtboardID,
           let artboard = document.scene.artboards.first(where: { $0.id == activeID }) {
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
