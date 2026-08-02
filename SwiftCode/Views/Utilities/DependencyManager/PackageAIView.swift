import SwiftUI

struct PackageAIView: View {
    @State private var platformManager = DependencyPlatformManager.shared
    @State private var inputPrompt: String = ""
    @State private var showFavoritesOnly: Bool = false

    var filteredChatHistory: [PackageAIChat] {
        if showFavoritesOnly {
            return platformManager.chatHistory.filter { $0.isFavorite }
        } else {
            return platformManager.chatHistory
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Info card
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("AI Package Co-Designer & Assistant", systemImage: "sparkles")
                                .font(.title2.bold())
                                .foregroundColor(.purple)
                            Spacer()

                            Toggle("Show Favorites Only", isOn: $showFavoritesOnly)
                                .toggleStyle(.checkbox)
                        }

                        Text("Explain dependencies, clear cyclic target paths, and request architectural suggestions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Prompt Templates card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Prompt Templates & Presets", systemImage: "square.stack.3d.up")
                            .font(.headline)
                            .foregroundColor(.blue)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: .infinity))], spacing: 12) {
                            ForEach(Array(platformManager.promptTemplates.keys), id: \.self) { key in
                                Button {
                                    if let p = platformManager.promptTemplates[key] {
                                        inputPrompt = p
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(key)
                                            .font(.caption.bold())
                                            .foregroundColor(.blue)
                                        Text(platformManager.promptTemplates[key] ?? "")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Interactive Chat Input Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Send Custom Prompt", systemImage: "paperplane")
                            .font(.headline)
                            .foregroundColor(.green)

                        HStack(spacing: 12) {
                            TextField("Ask the package assistant...", text: $inputPrompt)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(triggerAIQuery)

                            Button(action: triggerAIQuery) {
                                HStack {
                                    Image(systemName: "sparkles")
                                    Text("Ask Copilot")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .disabled(inputPrompt.isEmpty || platformManager.isOperationRunning)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Conversation History card
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Conversation Logs", systemImage: "text.bubble")
                            .font(.headline)
                            .foregroundColor(.orange)

                        if filteredChatHistory.isEmpty {
                            ContentUnavailableView(
                                "No Conversations Yet",
                                systemImage: "sparkles",
                                description: Text("Ask about module division, alternative packages, cyclic dependencies, or security practices.")
                            )
                            .padding(.vertical, 24)
                        } else {
                            VStack(spacing: 16) {
                                ForEach(filteredChatHistory) { chat in
                                    VStack(alignment: .leading, spacing: 10) {
                                        // User block
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "person.circle.fill")
                                                .foregroundColor(.secondary)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("You")
                                                    .font(.caption.bold())
                                                    .foregroundColor(.secondary)
                                                Text(chat.prompt)
                                                    .font(.body)
                                                    .padding(10)
                                                    .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                            }
                                            Spacer()

                                            Button {
                                                toggleFavoriteChat(chat.id)
                                            } label: {
                                                Image(systemName: chat.isFavorite ? "star.fill" : "star")
                                                    .foregroundColor(.yellow)
                                            }
                                            .buttonStyle(.plain)
                                        }

                                        // AI response block
                                        HStack(alignment: .top, spacing: 8) {
                                            Image(systemName: "sparkles")
                                                .foregroundColor(.blue)
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text("AI Co-Designer")
                                                    .font(.caption.bold())
                                                    .foregroundColor(.blue)
                                                Text(chat.response)
                                                    .font(.body)
                                                    .padding(10)
                                                    .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                            }
                                        }
                                    }
                                    .padding(.vertical, 8)

                                    if chat.id != filteredChatHistory.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("AI Assistant")
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
