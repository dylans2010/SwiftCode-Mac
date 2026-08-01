import SwiftUI

struct PackageAIView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var platformManager = DependencyPlatformManager.shared
    @State private var inputPrompt: String = ""
    @State private var selectedTemplate: String? = nil
    @State private var showFavoritesOnly: Bool = false

    var filteredChatHistory: [PackageAIChat] {
        if showFavoritesOnly {
            return platformManager.chatHistory.filter { $0.isFavorite }
        } else {
            return platformManager.chatHistory
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)

                Text("AI Package Co-Designer & Assistant")
                    .font(.title2.bold())

                Spacer()

                Toggle(showFavoritesOnly ? "Showing Favorites Only" : "Show Favorites Only", isOn: $showFavoritesOnly)
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            HSplitView {
                // Left Panel: Presets & Templates
                VStack(alignment: .leading, spacing: 20) {
                    Text("Prompt Templates")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(platformManager.promptTemplates.keys), id: \.self) { key in
                                Button {
                                    if let p = platformManager.promptTemplates[key] {
                                        inputPrompt = p
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key)
                                            .font(.caption.bold())
                                            .foregroundStyle(.blue)
                                        Text(platformManager.promptTemplates[key] ?? "")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }

                            Divider()

                            Text("Quick Saved Prompts")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)

                            ForEach(platformManager.savedPrompts, id: \.self) { p in
                                Button {
                                    inputPrompt = p
                                } label: {
                                    Text(p)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .foregroundStyle(.secondary)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.secondary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(20)
                .frame(width: 280, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))

                // Right Panel: Conversation timeline & chat input
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 18) {
                                if filteredChatHistory.isEmpty {
                                    VStack(spacing: 16) {
                                        Spacer()
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 40))
                                            .foregroundStyle(.blue)
                                        Text("How can I assist your Package Architecture today?")
                                            .font(.headline)
                                        Text("Ask about module division, alternative packages, circular dependencies, or security practices.")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                        Spacer()
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 300)
                                } else {
                                    ForEach(filteredChatHistory) { chat in
                                        VStack(alignment: .leading, spacing: 12) {
                                            // User block
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "person.circle.fill")
                                                    .font(.title3)
                                                    .foregroundStyle(.secondary)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("You")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.secondary)
                                                    Text(chat.prompt)
                                                        .font(.body)
                                                        .padding(12)
                                                        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                                                }
                                                Spacer()

                                                Button {
                                                    toggleFavoriteChat(chat.id)
                                                } label: {
                                                    Image(systemName: chat.isFavorite ? "star.fill" : "star")
                                                        .foregroundStyle(.yellow)
                                                }
                                                .buttonStyle(.plain)
                                            }

                                            // AI response block
                                            HStack(alignment: .top, spacing: 10) {
                                                Image(systemName: "sparkles")
                                                    .font(.title3)
                                                    .foregroundStyle(.blue)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("AI Co-Designer")
                                                        .font(.caption.bold())
                                                        .foregroundStyle(.blue)
                                                    Text(chat.response)
                                                        .font(.body)
                                                        .padding(12)
                                                        .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                                }
                                            }
                                        }
                                        .id(chat.id)
                                        .padding(.horizontal)
                                    }
                                }
                            }
                            .padding(.vertical, 20)
                        }
                        .onChange(of: platformManager.chatHistory) { _, _ in
                            if let last = platformManager.chatHistory.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Input Bar
                    HStack(spacing: 12) {
                        TextField("Ask the package assistant...", text: $inputPrompt)
                            .textFieldStyle(.plain)
                            .padding(12)
                            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                            .onSubmit {
                                triggerAIQuery()
                            }

                        Button {
                            triggerAIQuery()
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .padding(10)
                                .background(inputPrompt.isEmpty ? Color.gray : Color.blue, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .disabled(inputPrompt.isEmpty || platformManager.isOperationRunning)
                    }
                    .padding(16)
                    .background(Color(NSColor.windowBackgroundColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func triggerAIQuery() {
        let p = inputPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        inputPrompt = ""
        Task {
            _ = await platformManager.askAIAssistant(prompt: p)
        }
    }

    private func toggleFavoriteChat(_ id: UUID) {
        if let idx = platformManager.chatHistory.firstIndex(where: { $0.id == id }) {
            platformManager.chatHistory[idx].isFavorite.toggle()
            platformManager.saveState()
        }
    }
}
