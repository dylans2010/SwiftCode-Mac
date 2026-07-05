import SwiftUI

struct OnDeviceAIView: View {
    @ObservedObject var controller: ChatController
    @State private var inputText = ""
    @State private var useContext = true
    @State private var streamedResponse = ""

    var body: some View {
        ZStack {
            AssistantTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headerCard
                    transcript
                    composer
                }
                .padding()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: controller.messages)
        .navigationTitle("Apple Intelligence")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        HStack(alignment: .top) {
            AssistantSectionHeader(
                eyebrow: "On Device AI",
                title: "Private Local Assistance",
                subtitle: "Stream responses on device with the same rebuilt assistant interface and responsive controls."
            )
            Spacer()
            Text(DeviceUtilityManager.shared.getCapabilityLevel().rawValue.capitalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.10))
                .clipShape(Capsule())
        }
        .padding(20)
        .assistantGlassCard()
    }

    private var transcript: some View {
        VStack(spacing: 12) {
            ForEach(controller.messages) { message in
                ChatMessageBubble(message: message)
            }
            if !streamedResponse.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Streaming")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.72))
                        Text(streamedResponse)
                            .foregroundStyle(.white)
                    }
                    .padding(16)
                    .background(AssistantTheme.assistantBubble)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    Spacer(minLength: 56)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .assistantGlassCard()
    }

    private var composer: some View {
        VStack(spacing: 12) {
            Toggle("Use Project Context", isOn: $useContext)
                .toggleStyle(.switch)
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                TextField("Ask Apple Intelligence", text: $inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(16)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(.white)

                Button {
                    let prompt = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !prompt.isEmpty else { return }
                    inputText = ""
                    streamedResponse = ""
                    Task {
                        controller.messages.append(ChatMessage(role: .user, content: prompt, timestamp: Date()))
                        do {
                            for try await chunk in OnDeviceAIManager.shared.streamResponse(for: useContext ? "[Context Aware]\n\n\(prompt)" : prompt) {
                                streamedResponse = chunk
                            }
                            let cleaned = LLMService.shared.sanitizeResponse(streamedResponse, relativeTo: prompt)
                            if !cleaned.isEmpty {
                                controller.messages.append(ChatMessage(role: .assistant, content: cleaned, timestamp: Date()))
                            }
                            streamedResponse = ""
                        } catch {
                            controller.messages.append(ChatMessage(role: .assistant, content: error.localizedDescription, timestamp: Date()))
                        }
                    }
                } label: {
                    Label("Send", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(AssistantPrimaryButtonStyle())
                .frame(maxWidth: 140)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .assistantGlassCard()
    }
}
