// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Services/LocalModelManager.swift
// Adapted for Ycode: Local model inventory (CoreML/GGUF/ONNX by extension) in ~/Documents/Models. AppSettings replaced by UserDefaults keys; ObservableObject -> @Observable.

import Foundation
import Observation
import Observation

// MARK: - Local Model Info

struct LocalModelInfo: Identifiable {
    let id: String
    var name: String
    var fileName: String
    var fileSize: Int64
    var type: ModelType
    var isLoaded: Bool = false
    var url: URL

    enum ModelType: String {
        case coreML  = "CoreML"
        case gguf    = "GGUF"
        case onnx    = "ONNX"
        case other   = "Other"

        var icon: String {
            switch self {
            case .coreML:  return "cpu.fill"
            case .gguf:    return "gearshape.fill"
            case .onnx:    return "bolt.fill"
            case .other:   return "doc.fill"
            }
        }
    }

    var formattedSize: String {
        let mb = Double(fileSize) / 1_048_576
        if mb >= 1000 { return String(format: "%.1f GB", mb / 1024) }
        return String(format: "%.1f MB", mb)
    }
}

// MARK: - Local Model Manager

@MainActor
@Observable
final class LocalModelManager {
    static let shared = LocalModelManager()

    /// NOTE (honest): like Legacy, "loading" a model only records a
    /// preference (selected model id + enabled flag). No model is actually
    /// executed by this manager; the runtime that consumes the preference
    /// does the loading.
    private static let selectedModelKey = "com.swiftcode.localModel.selectedModel"
    private static let enabledKey = "com.swiftcode.localModel.enabled"
    private let defaults = UserDefaults.standard

    var models: [LocalModelInfo] = []
    var isScanning = false
    var loadedModelId: String?

    private var modelsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Models")
    }

    private init() {
        ensureModelsDirectory()
        Task { await scanModels() }
    }

    // MARK: - Directory

    private func ensureModelsDirectory() {
        try? FileManager.default.createDirectory(
            at: modelsDirectory, withIntermediateDirectories: true
        )
    }

    // MARK: - Scan

    func scanModels() async {
        isScanning = true
        defer { isScanning = false }

        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: modelsDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: .skipsHiddenFiles
        ) else { return }

        var found: [LocalModelInfo] = []
        for url in contents {
            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }

            let ext = url.pathExtension.lowercased()
            let type: LocalModelInfo.ModelType
            switch ext {
            case "mlmodel", "mlpackage", "mlmodelc": type = .coreML
            case "gguf", "ggml", "bin": type = .gguf
            case "onnx": type = .onnx
            default: type = .other
            }

            let info = LocalModelInfo(
                id: url.lastPathComponent,
                name: url.deletingPathExtension().lastPathComponent,
                fileName: url.lastPathComponent,
                fileSize: Int64(values.fileSize ?? 0),
                type: type,
                isLoaded: loadedModelId == url.lastPathComponent,
                url: url
            )
            found.append(info)
        }

        models = found.sorted { $0.name < $1.name }
    }

    // MARK: - Load / Unload

    func loadModel(_ model: LocalModelInfo) {
        // On iOS, CoreML models are loaded on-demand via MLModel API.
        // This sets the active model preference for AISuggestionEngine.
        loadedModelId = model.id
        // Legacy wrote these into AppSettings; Ycode keeps them in
        // UserDefaults under the same logical keys.
        defaults.set(model.fileName, forKey: Self.selectedModelKey)
        defaults.set(true, forKey: Self.enabledKey)
        refreshLoadedState()
    }

    func unloadCurrentModel() {
        loadedModelId = nil
        defaults.set(false, forKey: Self.enabledKey)
        refreshLoadedState()
    }

    private func refreshLoadedState() {
        for idx in models.indices {
            models[idx].isLoaded = models[idx].id == loadedModelId
        }
    }

    // MARK: - Delete

    func deleteModel(_ model: LocalModelInfo) throws {
        try FileManager.default.removeItem(at: model.url)
        models.removeAll { $0.id == model.id }
        if loadedModelId == model.id { unloadCurrentModel() }
    }

    // MARK: - Import

    func importModel(from sourceURL: URL) throws {
        let destination = modelsDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        Task { await scanModels() }
    }
}
