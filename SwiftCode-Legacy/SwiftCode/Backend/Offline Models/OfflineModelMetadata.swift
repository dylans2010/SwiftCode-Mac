import Foundation

struct OfflineModelFile: Identifiable, Codable, Hashable {
    var id: String { fileName }
    let fileName: String
    let downloadURL: URL
    let sizeBytes: Int64

    var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

struct OfflineModelMetadata: Identifiable, Codable {
    var id: String { modelName }
    let modelName: String
    let providerName: String
    let description: String
    let modelSize: String
    let modelSizeBytes: Int64
    let tags: [String]
    let downloadCount: Int
    let modelURL: URL
    let files: [OfflineModelFile]
    let isQuantized: Bool

    var preferredDownloadFile: OfflineModelFile? {
        let preferred = files.sorted { lhs, rhs in
            let leftScore = Self.priorityScore(for: lhs)
            let rightScore = Self.priorityScore(for: rhs)
            if leftScore == rightScore {
                return lhs.sizeBytes < rhs.sizeBytes
            }
            return leftScore < rightScore
        }
        return preferred.first
    }

    private static func priorityScore(for file: OfflineModelFile) -> Int {
        let name = file.fileName.lowercased()
        let ext = file.fileExtension

        if name.contains("mlx") || name.contains("ml-ex") {
            return 0
        }

        if ext == "gguf" {
            return name.contains("q") ? 1 : 2
        }

        if ext == "safetensors" {
            return 3
        }

        if ext == "bin" {
            return 4
        }

        return 99
    }
}
