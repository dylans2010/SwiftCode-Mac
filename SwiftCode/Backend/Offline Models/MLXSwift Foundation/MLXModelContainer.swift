import Foundation
import MLX

@MainActor
final class MLXModelContainer: ObservableObject {
    @Published var isLoaded = false
    @Published var modelName: String = ""

    private var model: (OfflineLanguageModel, OfflineTokenizer)?

    func loadModel(at url: URL) async throws {
        let modelDirectory = url
        let (model, tokenizer) = try await LLMModelFactory.shared.loadModel(from: modelDirectory)

        self.model = (model, tokenizer)
        self.modelName = modelDirectory.lastPathComponent
        self.isLoaded = true
    }

    func generate(prompt: String, onToken: @escaping (String) -> Void) async throws {
        guard let (model, tokenizer) = model else {
            throw NSError(domain: "MLXModelContainer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Model not loaded"])
        }

        let promptTokens = tokenizer.encode(text: prompt)

        var tokens = [Int]()
        for try await token in model.generate(tokens: promptTokens) {
            tokens.append(token)
            onToken(tokenizer.decode(tokens: [token]))

            if tokens.count > 1024 { break }
        }
    }

    func reset() {
        model = nil
        isLoaded = false
        modelName = ""
    }
}
