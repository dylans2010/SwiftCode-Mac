import Foundation
import MLX
import MLXNN
import MLXOptimizers
import MLXRandom

enum MLXIntegration {
    static func validateRuntime() {
        _ = Adam(learningRate: 1e-3)
        _ = GELU()
        MLXRandom.seed(42)
    }
}

protocol OfflineLanguageModel {
    func generate(tokens: [Int]) -> AsyncThrowingStream<Int, Error>
}

protocol OfflineTokenizer {
    func encode(text: String) -> [Int]
    func decode(tokens: [Int]) -> String
}

final class LLMModelFactory: Sendable {
    static let shared = LLMModelFactory()

    private let universalLoader = UniversalModelLoader()

    private init() {
        MLXIntegration.validateRuntime()
    }

    func loadModel(from directory: URL) async throws -> (OfflineLanguageModel, OfflineTokenizer) {
        let loaded = try await universalLoader.loadModel(from: directory)
        return (loaded.model, loaded.tokenizer)
    }
}
