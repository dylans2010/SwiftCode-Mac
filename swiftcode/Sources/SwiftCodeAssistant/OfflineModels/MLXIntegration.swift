import Foundation

public enum MLXRuntimeError: LocalizedError, Sendable {
    case runtimeUnavailable(details: String)
    case modelNotLoaded

    public var errorDescription: String? {
        switch self {
        case let .runtimeUnavailable(details):
            return "MLX inference is unavailable: \(details)"
        case .modelNotLoaded:
            return "No model loaded."
        }
    }
}

public enum MLXIntegration {
    public static func validateRuntime() throws {
        throw MLXRuntimeError.runtimeUnavailable(
            details: "The MLX Swift packages (MLX, MLXNN, MLXOptimizers, MLXRandom) are not a dependency of SwiftCodeAssistant, so no MLX runtime is linked into this target."
        )
    }

    public static var isRuntimeAvailable: Bool { false }
}

public protocol OfflineLanguageModel: Sendable {
    func generate(tokens: [Int]) -> AsyncThrowingStream<Int, Error>
}

public protocol OfflineTokenizer: Sendable {
    func encode(text: String) -> [Int]
    func decode(tokens: [Int]) -> String
}

public final class LLMModelFactory: Sendable {
    public static let shared = LLMModelFactory()

    private let universalLoader = UniversalModelLoader()

    private init() {}

    public func loadModel(from directory: URL) async throws -> (OfflineLanguageModel, OfflineTokenizer) {
        let loaded = try await universalLoader.loadModel(from: directory)
        return (loaded.model, loaded.tokenizer)
    }
}
