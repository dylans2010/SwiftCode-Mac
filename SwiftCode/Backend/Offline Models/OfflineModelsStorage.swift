import Foundation

struct InstalledOfflineModelMetadata: Codable {
    let modelName: String
    let modelSourceURL: String
    let addedOn: Date
    let totalSize: Int64
    let tokenCount: Int
    let downloadedFiles: [String]
    let modelVersion: String

    enum CodingKeys: String, CodingKey {
        case modelName = "ModelName"
        case modelSourceURL = "ModelSourceURL"
        case addedOn = "AddedOn"
        case totalSize = "TotalSize"
        case tokenCount = "TokenCount"
        case downloadedFiles = "DownloadedFiles"
        case modelVersion = "ModelVersion"
    }
}

struct InstalledOfflineModelRecord: Identifiable {
    let metadata: InstalledOfflineModelMetadata
    let folderName: String
    var validationStatus: String?

    var id: String { folderName }
    var modelName: String { metadata.modelName }
    var installDate: Date { metadata.addedOn }
    var localModelPath: String {
        OfflineModelsStorage.shared.modelDirectoryURL(for: folderName).path
    }

    var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: metadata.totalSize, countStyle: .file)
    }
}

final class OfflineModelsStorage {
    static let shared = OfflineModelsStorage()
    private init() {}

    private let offlineModelsFolderName = "Offline Models"
    private let metadataFileName = "metadata.plist"

    func offlineModelsDirectory(createIfNeeded: Bool = true) throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let offlineDirectory = documentsDirectory.appendingPathComponent(offlineModelsFolderName, isDirectory: true)

        if createIfNeeded {
            try createDirectoryIfNeeded(at: offlineDirectory)
        }

        return offlineDirectory
    }

    func modelDirectory(for modelName: String, createIfNeeded: Bool = true) throws -> URL {
        let directory = modelDirectoryURL(for: sanitizedFolderName(from: modelName))
        if createIfNeeded {
            try createDirectoryIfNeeded(at: directory)
        }
        return directory
    }

    func modelDirectoryURL(for folderName: String) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsDirectory
            .appendingPathComponent(offlineModelsFolderName, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    func metadataURL(for modelDirectory: URL) -> URL {
        modelDirectory.appendingPathComponent(metadataFileName)
    }

    func writeMetadata(_ metadata: InstalledOfflineModelMetadata, modelDirectory: URL) throws {
        try createDirectoryIfNeeded(at: modelDirectory)
        let metadataURL = metadataURL(for: modelDirectory)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    func readMetadata(modelDirectory: URL) throws -> InstalledOfflineModelMetadata {
        let data = try Data(contentsOf: metadataURL(for: modelDirectory))
        return try PropertyListDecoder().decode(InstalledOfflineModelMetadata.self, from: data)
    }

    func loadInstalledModelRecords() -> [InstalledOfflineModelRecord] {
        do {
            let directory = try offlineModelsDirectory(createIfNeeded: true)
            let modelDirectories = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            let records = modelDirectories.compactMap { directoryURL -> InstalledOfflineModelRecord? in
                let values = try? directoryURL.resourceValues(forKeys: [.isDirectoryKey])
                guard values?.isDirectory == true else { return nil }
                guard let metadata = try? readMetadata(modelDirectory: directoryURL) else { return nil }
                return InstalledOfflineModelRecord(metadata: metadata, folderName: directoryURL.lastPathComponent, validationStatus: nil)
            }

            return records.sorted { $0.installDate > $1.installDate }
        } catch {
            return []
        }
    }

    func createDirectoryIfNeeded(at directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func sanitizedFolderName(from modelName: String) -> String {
        modelName.replacingOccurrences(of: "/", with: "_")
    }
}
