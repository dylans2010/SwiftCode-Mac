import Foundation
import Observation

@Observable
@MainActor
public final class OfflineModelManager {
    public static let shared = OfflineModelManager()
    public static let defaultOfflineModelKey = "SwiftCode.ai.defaultOfflineModel"

    public var installedModels: [OfflineModelMetadata] = []
    public var installedModelRecords: [InstalledOfflineModelRecord] = []
    public var downloadingModels: Set<String> = []
    public var defaultOfflineModelName: String = UserDefaults.standard.string(forKey: OfflineModelManager.defaultOfflineModelKey) ?? ""

    private var validationStatusByFolderName: [String: String] = [:]

    private init() {
        loadInstalledModels()
    }

    public func validateRepositoryURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return false
        }
        do {
            _ = try HuggingFaceAPI.shared.parseRepositoryPath(url)
            return true
        } catch {
            return false
        }
    }

    public func fetchModelMetadataFromLink(_ urlString: String) async throws -> OfflineModelMetadata {
        guard let repositoryURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw OfflineModelError.invalidHuggingFaceURL
        }
        let metadata = try await HuggingFaceAPI.shared.fetchModel(from: repositoryURL)
        guard !metadata.files.isEmpty else {
            throw OfflineModelError.noCompatibleModelFiles
        }
        return metadata
    }

    public func installModelFromLink(url: String) async throws {
        let metadata = try await fetchModelMetadataFromLink(url)
        try await OfflineModelDownloader.shared.download(model: metadata)
        loadInstalledModels()
    }

    public func loadInstalledModels() {
        let records = OfflineModelsStorage.shared.loadInstalledModelRecords()
        installedModelRecords = records.map { record in
            var mutableRecord = record
            mutableRecord.validationStatus = validationStatusByFolderName[record.folderName]
            return mutableRecord
        }
        installedModels = installedModelRecords.map { record in
            OfflineModelMetadata(
                modelName: record.modelName,
                providerName: "Offline",
                description: "Locally stored model",
                modelSize: record.sizeDescription,
                modelSizeBytes: record.metadata.totalSize,
                tags: ["offline", "installed"],
                downloadCount: 0,
                modelURL: URL(string: record.metadata.modelSourceURL) ?? URL(fileURLWithPath: record.localModelPath),
                files: [],
                isQuantized: false
            )
        }
        ensureDefaultModelSelection()
    }

    public func registerInstalledModel(from model: OfflineModelMetadata, localPath: URL) {
        loadInstalledModels()
    }

    public func isModelInstalled(_ modelName: String) -> Bool {
        installedModelRecords.contains { $0.modelName == modelName }
    }

    public func removeModel(_ model: OfflineModelMetadata) {
        let url = OfflineModelsStorage.shared.modelDirectoryURL(for: OfflineModelsStorage.shared.sanitizedFolderName(from: model.modelName))
        try? FileManager.default.removeItem(at: url)
        validationStatusByFolderName.removeValue(forKey: url.lastPathComponent)
        loadInstalledModels()
        if defaultOfflineModelName == model.modelName {
            ensureDefaultModelSelection()
        }
    }

    public func setDefaultOfflineModel(_ modelName: String) {
        defaultOfflineModelName = modelName
        UserDefaults.standard.set(modelName, forKey: Self.defaultOfflineModelKey)
    }

    public func defaultOfflineModelRecord() -> InstalledOfflineModelRecord? {
        installedModelRecords.first(where: { $0.modelName == defaultOfflineModelName })
    }

    private func ensureDefaultModelSelection() {
        if installedModelRecords.contains(where: { $0.modelName == defaultOfflineModelName }) {
            return
        }
        if let firstInstalled = installedModelRecords.first {
            setDefaultOfflineModel(firstInstalled.modelName)
        } else {
            defaultOfflineModelName = ""
            UserDefaults.standard.removeObject(forKey: Self.defaultOfflineModelKey)
        }
    }

    public func updateValidationStatus(for modelName: String, status: String, clearLocalPath: Bool = false) {
        guard let record = installedModelRecords.first(where: { $0.modelName == modelName }) else { return }
        validationStatusByFolderName[record.folderName] = status
        loadInstalledModels()
    }

    public func modelDirectory(for modelName: String) -> URL {
        (try? OfflineModelsStorage.shared.modelDirectory(for: modelName, createIfNeeded: true))
            ?? OfflineModelsStorage.shared.modelDirectoryURL(for: OfflineModelsStorage.shared.sanitizedFolderName(from: modelName))
    }
}

public final class OfflineModelConverter: Sendable {
    public static let shared = OfflineModelConverter()
    private init() {}

    public enum Layout: Sendable {
        case mlxReady
        case safetensorsReady
        case ggufNeedsConversion
        case unknown
    }

    public func detectLayout(at url: URL) throws -> Layout {
        let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        let names = contents.map(\.lastPathComponent)
        if names.contains("weights.npz") { return .mlxReady }
        if names.contains(where: { $0.hasSuffix(".safetensors") }) { return .safetensorsReady }
        if names.contains(where: { $0.hasSuffix(".gguf") }) { return .ggufNeedsConversion }
        return .unknown
    }

    public func convertIfNecessary(at url: URL) async throws {
        switch try detectLayout(at: url) {
        case .mlxReady, .safetensorsReady:
            return
        case .ggufNeedsConversion:
            throw OfflineModelError.conversionUnavailable(reason: "GGUF models cannot be converted to MLX format in this app: no converter binary or MLX runtime is bundled.")
        case .unknown:
            throw OfflineModelError.noCompatibleModelFiles
        }
    }
}
