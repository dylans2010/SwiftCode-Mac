import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A live client for the public Hugging Face Hub API (Legacy
/// `HuggingFaceAPI`, Dylan's own code, ported under MIT). Lists MLX
/// models by download count and fetches one repository's file list; the
/// result is `OfflineModelMetadata`, consumed by `OfflineModelDownloader`.
/// List results are cached in UserDefaults for one hour, exactly as Legacy
/// cached them; a single-repository fetch is never cached.
public final class HuggingFaceAPI: @unchecked Sendable {
    public static let shared = HuggingFaceAPI()
    private init() {}

    private let baseURL = URL(string: "https://huggingface.co/api/models")!
    private let cacheKey = "SwiftCode.huggingface.models.cache"
    private let cacheTimestampKey = "SwiftCode.huggingface.models.cache.timestamp"
    private let cacheDuration: TimeInterval = 3600
    private let allowedExtensions = ["safetensors", "gguf", "bin", "json", "model", "txt"]

    public func fetchModels(forceRefresh: Bool = false) async throws -> [OfflineModelMetadata] {
        if !forceRefresh, let cached = getCachedModels() {
            return cached
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search", value: "mlx"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "25"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        let hfModels = try JSONDecoder().decode([HFModelResponse].self, from: data)
        let models = try await mapModels(hfModels)
        cacheModels(models)
        return models
    }

    public func fetchModel(from repositoryURL: URL) async throws -> OfflineModelMetadata {
        let modelPath = try parseRepositoryPath(repositoryURL)
        return try await fetchModel(modelPath: modelPath)
    }

    public func fetchModel(modelPath: String) async throws -> OfflineModelMetadata {
        let details = try await fetchModelDetails(modelId: modelPath)
        return mapDetails(modelPath: modelPath, details: details)
    }

    public func parseRepositoryPath(_ repositoryURL: URL) throws -> String {
        guard repositoryURL.scheme?.lowercased().hasPrefix("http") == true,
              repositoryURL.host?.lowercased() == "huggingface.co" else {
            throw OfflineModelError.invalidHuggingFaceURL
        }
        let parts = repositoryURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            throw OfflineModelError.invalidHuggingFaceURL
        }
        return "\(parts[0])/\(parts[1])"
    }

    private func mapModels(_ hfModels: [HFModelResponse]) async throws -> [OfflineModelMetadata] {
        var mapped: [OfflineModelMetadata] = []
        for hf in hfModels {
            do {
                let metadata = try await fetchModel(modelPath: hf.modelId)
                mapped.append(metadata)
            } catch {
                continue
            }
        }
        return mapped
    }

    private func mapDetails(modelPath: String, details: HFModelDetailsResponse) -> OfflineModelMetadata {
        let files = (details.siblingFiles ?? []).compactMap { file -> OfflineModelFile? in
            let ext = URL(fileURLWithPath: file.filename).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { return nil }
            guard let encodedPath = file.filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let downloadURL = URL(string: "https://huggingface.co/\(modelPath)/resolve/main/\(encodedPath)") else {
                return nil
            }
            return OfflineModelFile(
                fileName: file.filename,
                downloadURL: downloadURL,
                sizeBytes: Int64(file.lfs?.size ?? file.size ?? 0)
            )
        }
        let totalBytes = files.reduce(0) { $0 + $1.sizeBytes }
        return OfflineModelMetadata(
            modelName: details.modelId,
            providerName: details.author ?? details.modelId.components(separatedBy: "/").first ?? "Unknown",
            description: details.description ?? "Hugging Face model: \(details.modelId)",
            modelSize: totalBytes > 0 ? Self.formatBytes(Int(totalBytes)) : "Unknown",
            modelSizeBytes: totalBytes,
            tags: details.tags ?? [],
            downloadCount: details.downloads ?? 0,
            modelURL: URL(string: "https://huggingface.co/\(details.modelId)") ?? baseURL,
            files: files,
            isQuantized: (details.tags ?? []).contains(where: { $0.localizedCaseInsensitiveContains("quant") })
        )
    }

    private func fetchModelDetails(modelId: String) async throws -> HFModelDetailsResponse {
        guard let encoded = modelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://huggingface.co/api/models/\(encoded)") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(HFModelDetailsResponse.self, from: data)
    }

    private static func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func cacheModels(_ models: [OfflineModelMetadata]) {
        if let data = try? JSONEncoder().encode(models) {
            UserDefaults.standard.set(data, forKey: cacheKey)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
        }
    }

    private func getCachedModels() -> [OfflineModelMetadata]? {
        let timestamp = UserDefaults.standard.double(forKey: cacheTimestampKey)
        guard Date().timeIntervalSince1970 - timestamp < cacheDuration else { return nil }
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let models = try? JSONDecoder().decode([OfflineModelMetadata].self, from: data) else {
            return nil
        }
        return models
    }
}

private struct HFModelResponse: Decodable {
    let modelId: String
}

private struct HFModelDetailsResponse: Decodable {
    let modelId: String
    let author: String?
    let downloads: Int?
    let tags: [String]?
    let description: String?
    let siblingFiles: [HFModelFile]?

    enum CodingKeys: String, CodingKey {
        case modelId = "id"
        case author
        case downloads
        case tags
        case description = "cardData"
        case siblingFiles = "siblings"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        modelId = try container.decode(String.self, forKey: .modelId)
        author = try container.decodeIfPresent(String.self, forKey: .author)
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        siblingFiles = try container.decodeIfPresent([HFModelFile].self, forKey: .siblingFiles)
        if let card = try? container.decode(HFCardData.self, forKey: .description) {
            description = card.summary ?? card.description
        } else {
            description = nil
        }
    }
}

private struct HFCardData: Decodable {
    let summary: String?
    let description: String?
}

private struct HFModelFile: Decodable {
    let filename: String
    let size: Int?
    let lfs: HFModelLFS?

    enum CodingKeys: String, CodingKey {
        case filename = "rfilename"
        case size
        case lfs
    }
}

private struct HFModelLFS: Decodable {
    let size: Int?
}
