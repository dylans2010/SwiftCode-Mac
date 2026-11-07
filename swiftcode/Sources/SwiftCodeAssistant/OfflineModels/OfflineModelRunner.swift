import Foundation
import Observation

@MainActor
@Observable
public final class OfflineModelRunner {
    public static let shared = OfflineModelRunner()
    private init() {}

    private let container = MLXModelContainer()
    private var loadedModelPath: String?

    public var isModelLoaded: Bool { container.isLoaded }
    public var loadedModelName: String { container.modelName }

    public func loadModel(at url: URL) async throws {
        if loadedModelPath == url.path && container.isLoaded { return }

        try await OfflineModelConverter.shared.convertIfNecessary(at: url)
        try await container.loadModel(at: url)
        loadedModelPath = url.path
    }

    public func generateResponse(prompt: String) async throws -> String {
        var response = ""
        try await streamResponse(prompt: prompt) { token in
            response += token
        }
        return response
    }

    public func streamResponse(prompt: String, onToken: @escaping (String) -> Void) async throws {
        guard container.isLoaded else {
            throw MLXRuntimeError.modelNotLoaded
        }

        try await container.generate(prompt: prompt, onToken: onToken)
    }

    public func unloadModel() {
        container.reset()
        loadedModelPath = nil
    }
}
