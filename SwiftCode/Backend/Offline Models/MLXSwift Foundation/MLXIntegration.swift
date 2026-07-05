import Foundation
import MLX
import MLXNN
import MLXOptimizers
import MLXRandom

/// Centralized MLX bootstrap and validation utilities.
enum MLXIntegration {
    /// Ensures MLX modules are linked into the application binary and available at runtime.
    ///
    /// The implementation intentionally references symbols from multiple MLX packages
    /// so that SPM/Xcode will resolve and link all configured products.
    static func validateRuntime() {
        _ = Adam(learningRate: 1e-3)
        _ = GELU()
        MLXRandom.seed(42)
    }
}

/// Common abstraction for loaded offline models.
protocol OfflineLanguageModel {
    func generate(tokens: [Int]) -> AsyncThrowingStream<Int, Error>
}

/// Common abstraction for tokenizers.
protocol OfflineTokenizer {
    func encode(text: String) -> [Int]
    func decode(tokens: [Int]) -> String
}

/// Factory for creating and managing MLX-backed models and tokenizers.
final class LLMModelFactory {
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
