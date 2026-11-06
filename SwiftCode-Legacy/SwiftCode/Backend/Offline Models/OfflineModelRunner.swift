import Foundation

@MainActor
final class OfflineModelRunner: ObservableObject {
    static let shared = OfflineModelRunner()
    private init() {}

    private let container = MLXModelContainer()
    private var loadedModelPath: String?

    func loadModel(at url: URL) async throws {
        if loadedModelPath == url.path && container.isLoaded { return }

        try await OfflineModelConverter.shared.convertIfNecessary(at: url)
        try await container.loadModel(at: url)
        loadedModelPath = url.path
    }

    func generateResponse(prompt: String) async throws -> String {
        var response = ""
        try await streamResponse(prompt: prompt) { token in
            response += token
        }
        return response
    }

    func streamResponse(prompt: String, onToken: @escaping (String) -> Void) async throws {
        guard container.isLoaded else {
            throw NSError(domain: "OfflineModelRunner", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model loaded"])
        }

        try await container.generate(prompt: prompt, onToken: onToken)
    }
}
