import SwiftUI
import SwiftCodeIDECore
import SwiftCodeAssistant

struct DocumentationAIAssistantView: View {
    var symbol: DocSymbol?

    @State private var selectedPreset = "Explain this API."
    @State private var customPrompt = ""
    @State private var output = ""
    @State private var providerLine = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private static let presets = [
        "Explain this API.",
        "Generate Swift 6 documentation.",
        "Create usage tutorial.",
        "Concurrency & Sendable analysis.",
        "Platform compatibility report.",
        "Architectural integration patterns.",
        "SwiftData & Persistence guidelines.",
        "Generate Unit Tests sample.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Local AI Co-Pilot")
                .font(.title2.bold())
            if let symbol {
                Text("\(symbol.name) · \(symbol.framework) · \(symbol.kind)")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Select a symbol from the sidebar to ask about it.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.presets, id: \.self) { preset in
                        Button {
                            selectedPreset = preset
                            customPrompt = preset
                        } label: {
                            Text(preset)
                                .font(.caption)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(selectedPreset == preset
                                            ? Color.accentColor.opacity(0.15)
                                            : Color.secondary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                TextField("Custom or pre-selected prompt...", text: $customPrompt)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { if customPrompt.isEmpty { customPrompt = selectedPreset } }
                Button("Ask") { ask() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isProcessing || customPrompt.trimmingCharacters(in: .whitespaces).isEmpty || symbol == nil)
            }

            if isProcessing {
                ProgressView("Asking the configured provider…")
            }
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
                    .textSelection(.enabled)
            }
            if !providerLine.isEmpty {
                Text(providerLine)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .border(Color.secondary.opacity(0.3))
            }
            Spacer()
        }
        .padding()
    }

    private func llmService() -> LLMToolCompletionService {
        let services = CodingAssistantServices.shared
        var overrides: [ProviderKind: AssistantProvider] = [:]
        if let override = services.providerOverride {
            for kind in ProviderKind.allCases {
                if let provider = override(kind) { overrides[kind] = provider }
            }
        }
        return LLMToolCompletionService(backends: services.backends(), providerOverrides: overrides)
    }

    private func ask() {
        guard let symbol, !customPrompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isProcessing = true
        output = ""
        providerLine = ""
        errorMessage = nil
        let prompt = customPrompt
        Task {
            do {
                let service = llmService()
                let userText = """
                \(prompt)

                Symbol: \(symbol.name)
                Framework: \(symbol.framework)
                Kind: \(symbol.kind)
                Availability: \(symbol.availability)
                Summary: \(symbol.summary)
                Declaration:
                \(symbol.syntax)
                """
                let completion = try await service.complete(
                    systemPrompt: "You are a documentation assistant for Apple SDKs. Answer from the symbol details given; say plainly when the details do not answer the question instead of inventing API surface.",
                    userText: userText)
                await MainActor.run {
                    output = completion.text
                    providerLine = "Answered by \(completion.provider.displayName)"
                        + (completion.model.map { " · model \($0)" } ?? "")
                        + (completion.truncated ? " · response truncated" : "")
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
}
