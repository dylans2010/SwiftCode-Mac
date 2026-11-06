import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Downloads an offline model's files from Hugging Face into the storage
/// directory (Legacy `OfflineModelDownloader`). Behaviour change, stated
/// plainly: Legacy streamed each file to disk with a
/// `URLSessionDownloadDelegate`; this port downloads with
/// `URLSession.data(from:)` and writes the bytes out, because the delegate
/// download task is not portable to the Linux build of this target. Large
/// model files therefore buffer in memory during download. Progress,
/// speed, remaining-time, cancellation, pending-download resume and the
/// installed-metadata write are otherwise Legacy's own. There is no
/// notification on completion: Legacy called a `NotificationManager` that
/// does not exist in the destination.
@Observable
@MainActor
public final class OfflineModelDownloader {
    public static let shared = OfflineModelDownloader()
    private init() {}

    private let pendingModelKey = "SwiftCode.pendingOfflineModelDownload"

    public var downloadPercentage: Double = 0
    public var bytesDownloaded: Int64 = 0
    public var totalBytesToDownload: Int64 = 0
    public var bytesRemaining: Int64 = 0
    public var downloadSpeed: String = "0 KB/s"
    public var remainingTime: String = "Unknown"
    public var currentFileName: String = ""
    public var isDownloading = false
    public var activeModel: OfflineModelMetadata?
    public var lastErrorMessage: String?

    private var downloadRunnerTask: Task<Void, Never>?
    private var pendingBackgroundModel: OfflineModelMetadata?

    public var dataRemainingDescription: String {
        ByteCountFormatter.string(fromByteCount: bytesRemaining, countStyle: .file)
    }

    public var downloadedDescription: String {
        ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
    }

    public var totalDescription: String {
        ByteCountFormatter.string(fromByteCount: totalBytesToDownload, countStyle: .file)
    }

    public var progressLine: String {
        "\(Int(downloadPercentage))% • \(downloadedDescription) / \(totalDescription) • \(remainingTime) remaining"
    }

    public func startDownload(model: OfflineModelMetadata, onComplete: (() -> Void)? = nil) {
        if isDownloading, activeModel?.modelName == model.modelName { return }
        if isDownloading { cancelCurrentDownload() }
        downloadRunnerTask?.cancel()
        activeModel = model
        lastErrorMessage = nil
        downloadRunnerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.download(model: model)
                OfflineModelManager.shared.loadInstalledModels()
                self.lastErrorMessage = nil
                onComplete?()
            } catch {
                self.lastErrorMessage = self.detailedErrorMessage(for: error)
            }
        }
    }

    public func download(model: OfflineModelMetadata) async throws {
        if model.files.isEmpty {
            throw OfflineModelError.noCompatibleModelFiles
        }
        resetProgress()
        pendingBackgroundModel = model
        persistPendingDownload(model)
        isDownloading = true
        defer {
            isDownloading = false
            pendingBackgroundModel = nil
            clearPersistedPendingDownload()
        }
        OfflineModelManager.shared.downloadingModels.insert(model.modelName)
        defer { OfflineModelManager.shared.downloadingModels.remove(model.modelName) }

        _ = try OfflineModelsStorage.shared.offlineModelsDirectory(createIfNeeded: true)
        let localModelDirectory = try OfflineModelsStorage.shared.modelDirectory(for: model.modelName, createIfNeeded: true)
        try ensureWritableDirectory(localModelDirectory)

        let totalBytes = model.modelSizeBytes > 0 ? model.modelSizeBytes : model.files.reduce(0) { $0 + $1.sizeBytes }
        try verifyStorageCapacity(requiredBytes: totalBytes)

        totalBytesToDownload = totalBytes
        var totalReceivedBytes: Int64 = 0
        let startDate = Date()

        for file in model.files {
            try Task.checkCancellation()
            currentFileName = file.fileName
            try await downloadFile(file: file, modelDirectory: localModelDirectory)
            totalReceivedBytes += file.sizeBytes
            updateProgress(receivedBytes: totalReceivedBytes, expectedBytes: totalBytes, startDate: startDate)
        }

        downloadPercentage = 100
        bytesDownloaded = totalBytes
        bytesRemaining = 0
        remainingTime = "0s"
        currentFileName = "Completed"

        let installedMetadata = InstalledOfflineModelMetadata(
            modelName: model.modelName,
            modelSourceURL: model.modelURL.absoluteString,
            addedOn: Date(),
            totalSize: totalBytes,
            tokenCount: 0,
            downloadedFiles: model.files.map(\.fileName),
            modelVersion: "main"
        )
        try OfflineModelsStorage.shared.writeMetadata(installedMetadata, modelDirectory: localModelDirectory)
        OfflineModelManager.shared.registerInstalledModel(from: model, localPath: localModelDirectory)
        if OfflineModelManager.shared.defaultOfflineModelName.isEmpty {
            OfflineModelManager.shared.setDefaultOfflineModel(model.modelName)
        }
    }

    public func resumePendingDownloadIfNeeded() async {
        guard !isDownloading else { return }
        guard let model = pendingBackgroundModel ?? persistedPendingDownload() else { return }
        do {
            try await download(model: model)
        } catch {
            lastErrorMessage = detailedErrorMessage(for: error)
        }
    }

    public func cancelCurrentDownload() {
        guard isDownloading else { return }
        downloadRunnerTask?.cancel()
    }

    private func resetProgress() {
        downloadPercentage = 0
        bytesDownloaded = 0
        totalBytesToDownload = 0
        bytesRemaining = 0
        downloadSpeed = "0 KB/s"
        remainingTime = "Unknown"
        currentFileName = ""
    }

    private func detailedErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if error is OfflineModelError {
            return "\(error.localizedDescription)\n\nFull error: \(nsError)"
        }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError {
            return "Cannot write model files due to insufficient permissions in the selected folder. Full error: \(nsError)"
        }
        if nsError.domain == NSURLErrorDomain {
            return "Network download failed. Full error: \(nsError)"
        }
        return "Full error: \(nsError)"
    }

    private func persistPendingDownload(_ model: OfflineModelMetadata) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        UserDefaults.standard.set(data, forKey: pendingModelKey)
    }

    private func clearPersistedPendingDownload() {
        UserDefaults.standard.removeObject(forKey: pendingModelKey)
    }

    private func persistedPendingDownload() -> OfflineModelMetadata? {
        guard let data = UserDefaults.standard.data(forKey: pendingModelKey),
              let model = try? JSONDecoder().decode(OfflineModelMetadata.self, from: data) else {
            return nil
        }
        return model
    }

    private func ensureWritableDirectory(_ directoryURL: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            throw OfflineModelError.cannotCreateDirectory(path: directoryURL.path, underlyingError: error)
        }
        guard FileManager.default.isWritableFile(atPath: directoryURL.path) else {
            throw OfflineModelError.noWritePermission(path: directoryURL.path)
        }
    }

    private func verifyStorageCapacity(requiredBytes: Int64) throws {
        guard let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let availableBytes = values.volumeAvailableCapacityForImportantUsage else {
            return
        }
        if Int64(availableBytes) < requiredBytes {
            throw OfflineModelError.insufficientStorage(requiredBytes: requiredBytes, availableBytes: Int64(availableBytes))
        }
    }

    private func downloadFile(file: OfflineModelFile, modelDirectory: URL) async throws {
        let (data, response) = try await URLSession.shared.data(from: file.downloadURL)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let destinationURL = modelDirectory.appendingPathComponent(file.fileName)
        do {
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try data.write(to: destinationURL, options: .atomic)
        } catch {
            throw OfflineModelError.failedToMoveDownloadedFile(from: file.downloadURL.absoluteString, to: destinationURL.path, underlyingError: error)
        }
    }

    private func updateProgress(receivedBytes: Int64, expectedBytes: Int64, startDate: Date) {
        let normalizedExpectedBytes = max(expectedBytes, 1)
        let progress = min(100.0, (Double(receivedBytes) / Double(normalizedExpectedBytes)) * 100)
        downloadPercentage = progress
        bytesDownloaded = receivedBytes
        bytesRemaining = max(normalizedExpectedBytes - receivedBytes, 0)
        totalBytesToDownload = normalizedExpectedBytes
        let elapsed = max(Date().timeIntervalSince(startDate), 0.1)
        let bytesPerSecond = Double(receivedBytes) / elapsed
        downloadSpeed = ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
        let remainingBytes = max(Double(normalizedExpectedBytes - receivedBytes), 0)
        if bytesPerSecond > 0 {
            remainingTime = "\(Int(remainingBytes / bytesPerSecond))s"
        } else {
            remainingTime = "Unknown"
        }
    }
}


// Ported from Legacy `SwiftCode/Backend/Offline Models/OfflineModelDownloader.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: DownloadTaskDelegate.

private final class DownloadTaskDelegate: NSObject, URLSessionDownloadDelegate {
    private let modelFolderName: String
    private let relativeFilePath: String
    private let onProgress: @MainActor (Int64, Int64) -> Void
    private let onComplete: @MainActor (URL?, URLResponse?, Error?) -> Void
    private var finalizedURL: URL?
    private var response: URLResponse?
    private var fileMoveError: Error?

    init(
        modelFolderName: String,
        relativeFilePath: String,
        onProgress: @escaping @MainActor (Int64, Int64) -> Void,
        onComplete: @escaping @MainActor (URL?, URLResponse?, Error?) -> Void
    ) {
        self.modelFolderName = modelFolderName
        self.relativeFilePath = relativeFilePath
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        response = downloadTask.response

        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let offlineModelsDirectory = documentsDirectory.appendingPathComponent("Offline Models", isDirectory: true)
        let modelDirectory = offlineModelsDirectory.appendingPathComponent(modelFolderName, isDirectory: true)
        let destinationURL = modelDirectory.appendingPathComponent(relativeFilePath)

        do {
            try FileManager.default.createDirectory(at: offlineModelsDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(at: location, to: destinationURL)
            finalizedURL = destinationURL
        } catch {
            fileMoveError = OfflineModelError.failedToMoveDownloadedFile(
                from: location.path,
                to: destinationURL.path,
                underlyingError: error
            )
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task { @MainActor in
            onProgress(totalBytesWritten, totalBytesExpectedToWrite)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        Task { @MainActor in
            let completionError = error ?? fileMoveError
            onComplete(finalizedURL, response, completionError)
        }
        session.finishTasksAndInvalidate()
    }
}
