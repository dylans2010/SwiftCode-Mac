import Foundation
import Observation

@MainActor
@Observable
public final class MLXModelContainer {
    public var isLoaded = false
    public var modelName: String = ""

    private var model: (OfflineLanguageModel, OfflineTokenizer)?

    public init() {}

    public func loadModel(at url: URL) async throws {
        let modelDirectory = url
        let (model, tokenizer) = try await LLMModelFactory.shared.loadModel(from: modelDirectory)

        self.model = (model, tokenizer)
        self.modelName = modelDirectory.lastPathComponent
        self.isLoaded = true
    }

    public func generate(prompt: String, onToken: @escaping (String) -> Void) async throws {
        guard let (model, tokenizer) = model else {
            throw MLXRuntimeError.modelNotLoaded
        }

        let promptTokens = tokenizer.encode(text: prompt)

        var tokens = [Int]()
        for try await token in model.generate(tokens: promptTokens) {
            tokens.append(token)
            onToken(tokenizer.decode(tokens: [token]))

            if tokens.count > 1024 { break }
        }
    }

    public func reset() {
        model = nil
        isLoaded = false
        modelName = ""
    }
}
