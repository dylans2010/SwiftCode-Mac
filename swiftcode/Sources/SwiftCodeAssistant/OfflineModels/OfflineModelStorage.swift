import Foundation

public struct InstalledOfflineModelMetadata: Codable, Sendable {
    public let modelName: String
    public let modelSourceURL: String
    public let addedOn: Date
    public let totalSize: Int64
    public let tokenCount: Int
    public let downloadedFiles: [String]
    public let modelVersion: String

    public init(
        modelName: String, modelSourceURL: String, addedOn: Date, totalSize: Int64,
        tokenCount: Int, downloadedFiles: [String], modelVersion: String
    ) {
        self.modelName = modelName
        self.modelSourceURL = modelSourceURL
        self.addedOn = addedOn
        self.totalSize = totalSize
        self.tokenCount = tokenCount
        self.downloadedFiles = downloadedFiles
        self.modelVersion = modelVersion
    }

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

public struct InstalledOfflineModelRecord: Identifiable, Sendable {
    public let metadata: InstalledOfflineModelMetadata
    public let folderName: String
    public var validationStatus: String?

    public init(metadata: InstalledOfflineModelMetadata, folderName: String, validationStatus: String? = nil) {
        self.metadata = metadata
        self.folderName = folderName
        self.validationStatus = validationStatus
    }

    public var id: String { folderName }
    public var modelName: String { metadata.modelName }
    public var installDate: Date { metadata.addedOn }
    public var localModelPath: String {
        OfflineModelsStorage.shared.modelDirectoryURL(for: folderName).path
    }

    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: metadata.totalSize, countStyle: .file)
    }
}

public final class OfflineModelsStorage: @unchecked Sendable {
    public static let shared = OfflineModelsStorage()
    private init() {}

    private let offlineModelsFolderName = "OfflineModels"
    private let metadataFileName = "metadata.plist"

    public func offlineModelsDirectory(createIfNeeded: Bool = true) throws -> URL {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw OfflineModelError.cannotCreateDirectory(path: "Application Support", underlyingError: URLError(.fileDoesNotExist))
        }
        let directory = support.appendingPathComponent("SwiftCode", isDirectory: true)
            .appendingPathComponent(offlineModelsFolderName, isDirectory: true)
        if createIfNeeded {
            try createDirectoryIfNeeded(at: directory)
        }
        return directory
    }

    public func modelDirectory(for modelName: String, createIfNeeded: Bool = true) throws -> URL {
        let directory = modelDirectoryURL(for: sanitizedFolderName(from: modelName))
        if createIfNeeded {
            try createDirectoryIfNeeded(at: directory)
        }
        return directory
    }

    public func modelDirectoryURL(for folderName: String) -> URL {
        let documentsDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return documentsDirectory
            .appendingPathComponent("SwiftCode", isDirectory: true)
            .appendingPathComponent(offlineModelsFolderName, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    public func metadataURL(for modelDirectory: URL) -> URL {
        modelDirectory.appendingPathComponent(metadataFileName)
    }

    public func writeMetadata(_ metadata: InstalledOfflineModelMetadata, modelDirectory: URL) throws {
        try createDirectoryIfNeeded(at: modelDirectory)
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL(for: modelDirectory), options: .atomic)
    }

    public func readMetadata(modelDirectory: URL) throws -> InstalledOfflineModelMetadata {
        let data = try Data(contentsOf: metadataURL(for: modelDirectory))
        return try PropertyListDecoder().decode(InstalledOfflineModelMetadata.self, from: data)
    }

    public func loadInstalledModelRecords() -> [InstalledOfflineModelRecord] {
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

    public func createDirectoryIfNeeded(at directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    public func sanitizedFolderName(from modelName: String) -> String {
        modelName.replacingOccurrences(of: "/", with: "_")
    }
}
