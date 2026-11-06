// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Offline Models/MLXSwift Foundation/MLXIntegration.swift
//   (Legacy commit d51a8f0d)
//
// MLX GAP — stated plainly: this target (SwiftCodeAssistant) has NO MLX
// dependency (swiftcode/Package.swift contains no MLX product, and no MLX
// package is linked), so no MLX inference can run here. Legacy's
// `validateRuntime()` instantiated MLX symbols (`Adam`, `GELU`,
// `MLXRandom.seed`) purely to force the linker to keep the MLX products;
// that cannot be reproduced without the dependency, and faking it with a
// no-op would claim a runtime that does not exist. Instead, validation
// throws `MLXRuntimeError.runtimeUnavailable`, and every path that would
// execute a model through MLX throws the same typed error. Everything
// around the gap is real: the `OfflineLanguageModel` / `OfflineTokenizer`
// interfaces, the factory, and the loader's config/tokenizer/weights
// discovery (see UniversalModelLoader.swift). Adding MLX means adding the
// MLX Swift packages to Package.swift and restoring the MLX-backed
// builder; nothing in this file pretends that step has happened.

import Foundation

/// The MLX runtime is not available in this target.
public enum MLXRuntimeError: LocalizedError, Sendable {
    /// No MLX runtime is linked: token generation through an MLX model
    /// cannot run. Carries what was attempted, so the caller can say so.
    case runtimeUnavailable(details: String)
    /// A generation was attempted with no model loaded.
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

/// Centralized MLX bootstrap and validation utilities.
public enum MLXIntegration {
    /// Ensures MLX modules are linked into the application binary and
    /// available at runtime.
    ///
    /// Legacy referenced symbols from multiple MLX packages here so that
    /// SPM/Xcode would resolve and link all configured products. This
    /// target links no MLX product, so there is nothing to validate
    /// against: the call throws `MLXRuntimeError.runtimeUnavailable`
    /// instead of silently succeeding.
    public static func validateRuntime() throws {
        throw MLXRuntimeError.runtimeUnavailable(
            details: "The MLX Swift packages (MLX, MLXNN, MLXOptimizers, MLXRandom) are not a dependency of SwiftCodeAssistant, so no MLX runtime is linked into this target."
        )
    }

    /// Whether an MLX runtime is linked. Always false in this target
    /// until the MLX packages are added to Package.swift.
    public static var isRuntimeAvailable: Bool { false }
}

/// Common abstraction for loaded offline models.
public protocol OfflineLanguageModel: Sendable {
    func generate(tokens: [Int]) -> AsyncThrowingStream<Int, Error>
}

/// Common abstraction for tokenizers.
public protocol OfflineTokenizer: Sendable {
    func encode(text: String) -> [Int]
    func decode(tokens: [Int]) -> String
}

/// Factory for creating and managing MLX-backed models and tokenizers.
public final class LLMModelFactory: Sendable {
    public static let shared = LLMModelFactory()

    private let universalLoader = UniversalModelLoader()

    private init() {}

    public func loadModel(from directory: URL) async throws -> (OfflineLanguageModel, OfflineTokenizer) {
        // Loading itself (config, tokenizer, weights discovery) is real
        // and runs in UniversalModelLoader; only token generation needs
        // the MLX runtime, and the loaded model throws the typed error
        // when generation is attempted.
        let loaded = try await universalLoader.loadModel(from: directory)
        return (loaded.model, loaded.tokenizer)
    }
}
