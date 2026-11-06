import Foundation

@MainActor
final class OfflineModelManager: ObservableObject {
    static let shared = OfflineModelManager()
    static let defaultOfflineModelKey = "ai.defaultOfflineModel"

    @Published var installedModels: [OfflineModelMetadata] = []
    @Published var installedModelRecords: [InstalledOfflineModelRecord] = []
    @Published var downloadingModels: Set<String> = []
    @Published var defaultOfflineModelName: String = UserDefaults.standard.string(forKey: OfflineModelManager.defaultOfflineModelKey) ?? ""

    private var validationStatusByFolderName: [String: String] = [:]

    private init() {
        loadInstalledModels()
    }

    func validateRepositoryURL(_ urlString: String) -> Bool {
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

    func fetchModelMetadataFromLink(_ urlString: String) async throws -> OfflineModelMetadata {
        guard let repositoryURL = URL(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw OfflineModelError.invalidHuggingFaceURL
        }

        let metadata = try await HuggingFaceAPI.shared.fetchModel(from: repositoryURL)
        guard !metadata.files.isEmpty else {
            throw OfflineModelError.noCompatibleModelFiles
        }

        return metadata
    }

    func installModelFromLink(url: String) async throws {
        let metadata = try await fetchModelMetadataFromLink(url)
        try await OfflineModelDownloader.shared.download(model: metadata)
        loadInstalledModels()
    }

    func loadInstalledModels() {
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

    func registerInstalledModel(from model: OfflineModelMetadata, localPath: URL, installDate: Date = Date()) {
        loadInstalledModels()
    }

    func isModelInstalled(_ modelName: String) -> Bool {
        installedModelRecords.contains { $0.modelName == modelName }
    }

    func removeModel(_ model: OfflineModelMetadata) {
        let url = OfflineModelsStorage.shared.modelDirectoryURL(for: OfflineModelsStorage.shared.sanitizedFolderName(from: model.modelName))
        try? FileManager.default.removeItem(at: url)
        validationStatusByFolderName.removeValue(forKey: url.lastPathComponent)
        loadInstalledModels()

        if defaultOfflineModelName == model.modelName {
            ensureDefaultModelSelection()
        }
    }

    func setDefaultOfflineModel(_ modelName: String) {
        defaultOfflineModelName = modelName
        UserDefaults.standard.set(modelName, forKey: Self.defaultOfflineModelKey)
    }

    func defaultOfflineModelRecord() -> InstalledOfflineModelRecord? {
        installedModelRecords.first(where: { $0.modelName == defaultOfflineModelName })
    }

    private func ensureDefaultModelSelection() {
        if let existing = installedModelRecords.first(where: { $0.modelName == defaultOfflineModelName }) {
            if existing.modelName != defaultOfflineModelName {
                setDefaultOfflineModel(existing.modelName)
            }
            return
        }

        if let firstInstalled = installedModelRecords.first {
            setDefaultOfflineModel(firstInstalled.modelName)
        } else {
            defaultOfflineModelName = ""
            UserDefaults.standard.removeObject(forKey: Self.defaultOfflineModelKey)
        }
    }

    func updateValidationStatus(for modelName: String, status: String, clearLocalPath: Bool = false) {
        guard let record = installedModelRecords.first(where: { $0.modelName == modelName }) else { return }
        validationStatusByFolderName[record.folderName] = status
        loadInstalledModels()
    }

    func modelDirectory(for modelName: String) -> URL {
        (try? OfflineModelsStorage.shared.modelDirectory(for: modelName, createIfNeeded: true))
            ?? OfflineModelsStorage.shared.modelDirectoryURL(for: OfflineModelsStorage.shared.sanitizedFolderName(from: modelName))
    }
}
