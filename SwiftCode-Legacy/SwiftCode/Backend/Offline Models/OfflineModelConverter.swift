import Foundation

final class OfflineModelConverter: Sendable {
    static let shared = OfflineModelConverter()
    private init() {}

    func convertIfNecessary(at url: URL) async throws {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)

        let hasMLX = contents.contains { $0.lastPathComponent == "weights.npz" || $0.pathExtension == "safetensors" }
        if hasMLX {
            print("Model already MLX compatible or in safetensors format.")
            return
        }

        print("Converting model at \(url.path) to MLX format...")
    }
}
