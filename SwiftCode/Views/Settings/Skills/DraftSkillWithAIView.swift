import SwiftUI

struct DraftSkillWithAIView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var manager = AgentSkillManager.shared

    @State private var userPrompt = ""
    @State private var currentDraft = ""
    @State private var isDrafting = false
    @State private var errorMessage: String?
    @State private var showChangesPopover = false
    @State private var modificationRequest = ""
    @State private var activeTab = 0 // 0: Prompt, 1: Preview/Markdown

    // Track AI conversation message history so changes can be made with context
    @State private var conversationHistory: [AIMessage] = []

    private let systemPrompt = """
    You are an expert iOS/macOS software engineering assistant. Your task is to generate a professional SwiftCode coding skill file in markdown format (.SKILLS.md).
    You MUST output a valid YAML metadata frontmatter followed by clean, professional markdown guidelines.

    The format MUST be exactly like this:
    ---
    id: [Generate a valid UUID]
    author: SwiftCode AI
    version: 1.0.0
    tags: [comma-separated tags]
    recommendedTools: read_file, edit_file
    guidance: [semicolon-separated rule lists]
    ---
    # [Skill Name]

    [Brief summary of the skill]

    ## Guidelines
    - [Specific instruction 1]
    - [Specific instruction 2]

    ## Best Practices
    [Code blocks or detailed guidelines]

    IMPORTANT: Do not return any introduction or trailing conversational chatter. Only return the raw file content starting with the --- frontmatter block.
    """

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Workspace View", selection: $activeTab) {
                    Text("Prompt Studio").tag(0)
                    Text("Generated Preview").tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if activeTab == 0 {
                    promptPanel
                } else {
                    previewPanel
                }
            }
            .navigationTitle("Draft Skill with AI")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if !currentDraft.isEmpty {
                        Button("Save and Export Skill") {
                            saveDraftToSkills()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .frame(width: 580, height: 500)
    }

    private var promptPanel: some View {
        VStack(spacing: 16) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("What skill should the AI draft?", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundColor(.purple)

                    Text("Describe a coding pattern, library, framework, or performance standard you want the agent to follow when assisting you (e.g. 'SwiftUI NavigationStack best practices').")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $userPrompt)
                        .font(.body)
                        .frame(height: 100)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                        )
                }
                .padding(8)
            }
            .groupBoxStyle(ModernGroupBoxStyle())

            if isDrafting {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Streaming AI-Generated Skill Schema...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
                    .padding()
            }

            Button {
                Task { await generateDraft() }
            } label: {
                Label(currentDraft.isEmpty ? "Generate Custom Skill" : "Regenerate Draft", systemImage: "brain.fill")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.purple)
            .disabled(userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDrafting)

            if !currentDraft.isEmpty {
                Divider()

                HStack {
                    Button {
                        showChangesPopover = true
                    } label: {
                        Label("Request AI Iteration / Changes", systemImage: "text.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showChangesPopover) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Describe requested changes:")
                                .font(.headline)
                            TextEditor(text: $modificationRequest)
                                .frame(height: 80)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                                )
                            HStack {
                                Spacer()
                                Button("Cancel") { showChangesPopover = false }
                                Button("Apply Edits") {
                                    showChangesPopover = false
                                    Task { await iterateDraft() }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(modificationRequest.isEmpty)
                            }
                        }
                        .padding()
                        .frame(width: 320)
                    }
                }
            }

            Spacer()
        }
        .padding(24)
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if currentDraft.isEmpty {
                ContentUnavailableView("No Draft Generated Yet", systemImage: "doc.text.fill", description: Text("Draft a skill in Prompt Studio first."))
                    .padding()
            } else {
                Text("Generated Markdown Preview")
                    .font(.headline)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                ScrollView {
                    Text(currentDraft)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.15))
                        .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
    }

    // Call service to draft custom skill with optimized system prompt
    private func generateDraft() async {
        isDrafting = true
        errorMessage = nil
        currentDraft = ""
        conversationHistory = []

        let prompt = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = [AIMessage(role: .user, content: "Draft a coding skill guide for: \(prompt)")]

        do {
            try await OpenRouterService.shared.streamChat(
                messages: messages,
                model: settings.selectedAssistModelID,
                systemPrompt: systemPrompt
            ) { token in
                await MainActor.run {
                    currentDraft += token
                }
            }

            // Save state context for future modifications
            conversationHistory = messages + [AIMessage(role: .assistant, content: currentDraft)]
            activeTab = 1
        } catch {
            errorMessage = "AI Generation failed: \(error.localizedDescription)"
        }
        isDrafting = false
    }

    // Iterate on draft keeping track of context state
    private func iterateDraft() async {
        isDrafting = true
        errorMessage = nil
        currentDraft = ""

        let request = modificationRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        let newMessages = conversationHistory + [AIMessage(role: .user, content: "Modify the current draft according to this feedback: \(request). Return the complete, updated .SKILLS.md file starting with the --- YAML block.")]

        do {
            try await OpenRouterService.shared.streamChat(
                messages: newMessages,
                model: settings.selectedAssistModelID,
                systemPrompt: systemPrompt
            ) { token in
                await MainActor.run {
                    currentDraft += token
                }
            }

            // Update conversation history
            conversationHistory = newMessages + [AIMessage(role: .assistant, content: currentDraft)]
            modificationRequest = ""
            activeTab = 1
        } catch {
            errorMessage = "AI Iteration failed: \(error.localizedDescription)"
        }
        isDrafting = false
    }

    private func saveDraftToSkills() {
        let parser = SkillsParser()
        do {
            let parsed = try parser.parse(content: currentDraft)
            let filename = parsed.name.lowercased().replacingOccurrences(of: " ", with: "_") + ".SKILLS.md"
            let targetURL = await SkillsRuntime.shared.getBaseSkillsDirectory().appendingPathComponent(filename)

            try await SkillsRuntime.shared.saveSkill(parsed, at: targetURL)

            let loaded = await SkillsRuntime.shared.getAllSkills()
            await MainActor.run {
                manager.uploadedSkills = loaded
                dismiss()
            }
        } catch {
            errorMessage = "Failed to parse or save generated draft: \(error.localizedDescription)"
        }
    }
}
