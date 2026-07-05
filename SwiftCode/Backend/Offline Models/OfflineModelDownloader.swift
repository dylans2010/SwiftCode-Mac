import Foundation
import BackgroundTasks

@MainActor
final class OfflineModelDownloader: ObservableObject {
    static let shared = OfflineModelDownloader()
    private init() {}

    static let backgroundTaskIdentifier = "com.swiftcode.offline-model-download"
    private let pendingModelKey = "com.swiftcode.pendingOfflineModelDownload"

    @Published var downloadPercentage: Double = 0
    @Published var bytesDownloaded: Int64 = 0
    @Published var totalBytesToDownload: Int64 = 0
    @Published var bytesRemaining: Int64 = 0
    @Published var downloadSpeed: String = "0 KB/s"
    @Published var remainingTime: String = "Unknown"
    @Published var currentFileName: String = ""
    @Published var isDownloading = false
    @Published var activeModel: OfflineModelMetadata?
    @Published var lastErrorMessage: String?

    private var activeTask: URLSessionDownloadTask?
    private var activeSession: URLSession?
    private var activeDelegate: DownloadTaskDelegate?
    private var downloadRunnerTask: Task<Void, Never>?

    private var pendingBackgroundModel: OfflineModelMetadata?

    var dataRemainingDescription: String {
        ByteCountFormatter.string(fromByteCount: bytesRemaining, countStyle: .file)
    }

    var downloadedDescription: String {
        ByteCountFormatter.string(fromByteCount: bytesDownloaded, countStyle: .file)
    }

    var totalDescription: String {
        ByteCountFormatter.string(fromByteCount: totalBytesToDownload, countStyle: .file)
    }

    var progressLine: String {
        "\(Int(downloadPercentage))% • \(downloadedDescription) / \(totalDescription) • \(remainingTime) remaining"
    }

    func startDownload(model: OfflineModelMetadata, onComplete: (() -> Void)? = nil) {
        if isDownloading, activeModel?.modelName == model.modelName {
            return
        }

        if isDownloading {
            cancelCurrentDownload()
        }

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

    func download(model: OfflineModelMetadata) async throws {
        if model.files.isEmpty {
            throw OfflineModelError.noCompatibleModelFiles
        }

        resetProgress()
        pendingBackgroundModel = model
        persistPendingDownload(model)
        isDownloading = true
        defer {
            isDownloading = false
            activeTask = nil
            activeSession = nil
            activeDelegate = nil
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

        print("[OfflineModelDownloader] Starting download for \(model.modelName)")
        for file in model.files {
            currentFileName = file.fileName
            let _ = try await downloadFile(
                file: file,
                modelFolderName: OfflineModelsStorage.shared.sanitizedFolderName(from: model.modelName),
                alreadyReceivedBytes: totalReceivedBytes,
                totalExpectedBytes: totalBytes,
                startDate: startDate
            )

            totalReceivedBytes += file.sizeBytes
            updateProgress(receivedBytes: totalReceivedBytes, expectedBytes: totalBytes, startDate: startDate)
        }

        downloadPercentage = 100
        bytesDownloaded = totalBytes
        bytesRemaining = 0
        remainingTime = "0s"
        currentFileName = "Completed"
        print("[OfflineModelDownloader] Completed download for \(model.modelName)")

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
        NotificationManager.shared.sendOfflineModelDownloadedNotification(modelName: model.modelName)
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { task in
            Task { @MainActor in
                self.handleBackgroundProcessingTask(task)
            }
        }
    }

    func scheduleBackgroundDownloadContinuation() {
        guard isDownloading || persistedPendingDownload() != nil else { return }

        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("[OfflineModelDownloader] Scheduled background continuation task")
        } catch {
            print("[OfflineModelDownloader] Failed to schedule background task: \(error)")
        }
    }

    func resumePendingDownloadIfNeeded() async {
        guard !isDownloading else { return }
        guard let model = pendingBackgroundModel ?? persistedPendingDownload() else { return }

        do {
            try await download(model: model)
        } catch {
            print("[OfflineModelDownloader] Failed to resume pending background download: \(error)")
        }
    }

    func cancelCurrentDownload() {
        guard isDownloading else { return }
        print("[OfflineModelDownloader] Cancelling active download")
        downloadRunnerTask?.cancel()
        activeTask?.cancel()
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

        if let offlineError = error as? OfflineModelError {
            return "\(offlineError.localizedDescription)\n\nFull error: \(nsError)"
        }

        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteNoPermissionError {
            return "Cannot write model files due to insufficient permissions in the selected folder. Full error: \(nsError)"
        }

        if nsError.domain == NSURLErrorDomain {
            return "Network download failed. Full error: \(nsError)"
        }

        return "Full error: \(nsError)"
    }

    private func handleBackgroundProcessingTask(_ task: BGTask) {
        task.expirationHandler = {
            Task { @MainActor in
                self.cancelCurrentDownload()
            }
        }

        Task { @MainActor in
            await self.resumePendingDownloadIfNeeded()
            task.setTaskCompleted(success: !self.isDownloading)
        }
    }

    private func persistPendingDownload(_ model: OfflineModelMetadata) {
        guard let data = try? JSONEncoder().encode(model) else { return }
        UserDefaults.standard.set(data, forKey: pendingModelKey)
    }

    private func clearPersistedPendingDownload() {
        UserDefaults.standard.removeObject(forKey: pendingModelKey)
    }

    private func persistedPendingDownload() -> OfflineModelMetadata? {
        guard
            let data = UserDefaults.standard.data(forKey: pendingModelKey),
            let model = try? JSONDecoder().decode(OfflineModelMetadata.self, from: data)
        else {
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
        guard
            let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
            let availableBytes = values.volumeAvailableCapacityForImportantUsage
        else {
            return
        }

        if Int64(availableBytes) < requiredBytes {
            throw OfflineModelError.insufficientStorage(requiredBytes: requiredBytes, availableBytes: Int64(availableBytes))
        }
    }

    private func downloadFile(
        file: OfflineModelFile,
        modelFolderName: String,
        alreadyReceivedBytes: Int64,
        totalExpectedBytes: Int64,
        startDate: Date
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadTaskDelegate(
                modelFolderName: modelFolderName,
                relativeFilePath: file.fileName,
                onProgress: { bytesWritten, expectedToWrite in
                    let expectedBytes = expectedToWrite > 0 ? expectedToWrite : file.sizeBytes
                    let received = alreadyReceivedBytes + bytesWritten
                    self.updateProgress(receivedBytes: received, expectedBytes: max(totalExpectedBytes, alreadyReceivedBytes + expectedBytes), startDate: startDate)
                },
                onComplete: { finalizedURL, response, error in
                    self.activeTask = nil
                    self.activeSession = nil
                    self.activeDelegate = nil

                    if let error {
                        if (error as NSError).code == NSURLErrorCancelled {
                            continuation.resume(throwing: OfflineModelError.downloadCancelled)
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }

                    guard let finalizedURL, let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }

                    continuation.resume(returning: finalizedURL)
                }
            )

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: file.downloadURL)
            self.activeDelegate = delegate
            self.activeSession = session
            self.activeTask = task
            task.resume()
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
            let seconds = Int(remainingBytes / bytesPerSecond)
            remainingTime = "\(seconds)s"
        } else {
            remainingTime = "Unknown"
        }
    }
}

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
