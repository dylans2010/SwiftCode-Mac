// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Offline Models/MLXSwift Foundation/MLXModelContainer.swift
//   (Legacy commit d51a8f0d)
//
// MLX GAP (see MLXIntegration.swift): no MLX runtime is linked in this
// target, so `loadModel` succeeds only as far as real discovery goes —
// `LLMModelFactory` validates the directory's config, tokenizer and
// weights — and `generate` throws `MLXRuntimeError.runtimeUnavailable`
// through the loaded model. The container itself holds no fake output:
// it reports load state honestly and never invents tokens.
//
// Adaptation notes: Legacy was `ObservableObject` with `@Published`
// state; the destination uses `@Observable` (see LocalModelManager /
// OfflineModelManager), so this follows that convention. Legacy's
// `NSError(domain: "MLXModelContainer", code: 1, …)` for "model not
// loaded" is replaced with the typed `MLXRuntimeError.modelNotLoaded`.

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
