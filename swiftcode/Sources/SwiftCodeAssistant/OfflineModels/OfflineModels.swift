import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Errors for the offline-model subsystem (Legacy
/// `SwiftCode/Backend/Offline Models/`, Dylan's own code, ported under MIT).
/// The MLX-backed cases are gone with the MLX runtime: model inference itself
/// is honestly unavailable in this target (see `OfflineModelManager.swift`),
/// so this enum covers discovery, download, storage and conversion only.
public enum OfflineModelError: LocalizedError, Sendable {
    case invalidHuggingFaceURL
    case noCompatibleModelFiles
    case insufficientStorage(requiredBytes: Int64, availableBytes: Int64)
    case downloadCancelled
    case cannotCreateDirectory(path: String, underlyingError: Error)
    case noWritePermission(path: String)
    case failedToMoveDownloadedFile(from: String, to: String, underlyingError: Error)
    /// No converter binary exists in the destination: a GGUF/safetensors
    /// model cannot be turned into an MLX model here.
    case conversionUnavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .invalidHuggingFaceURL:
            return "Please provide a valid Hugging Face repository link."
        case .noCompatibleModelFiles:
            return "No compatible model files were found (.safetensors, .gguf, .bin)."
        case let .insufficientStorage(requiredBytes, availableBytes):
            let required = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
            let available = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
            return "Insufficient storage. Required \(required), available \(available)."
        case .downloadCancelled:
            return "Download cancelled."
        case let .cannotCreateDirectory(path, underlyingError):
            return "Unable to create download folder at \(path). \(underlyingError.localizedDescription)"
        case let .noWritePermission(path):
            return "No write permission for download folder: \(path). Please choose a writable app container directory."
        case let .failedToMoveDownloadedFile(from, to, underlyingError):
            return "Downloaded file could not be finalized from \(from) to \(to). \(underlyingError.localizedDescription)"
        case let .conversionUnavailable(reason):
            return "Model conversion is unavailable: \(reason)"
        }
    }
}

/// One downloadable file of an offline model (Legacy `OfflineModelFile`).
public struct OfflineModelFile: Identifiable, Codable, Hashable, Sendable {
    public var id: String { fileName }
    public let fileName: String
    public let downloadURL: URL
    public let sizeBytes: Int64

    public init(fileName: String, downloadURL: URL, sizeBytes: Int64) {
        self.fileName = fileName
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
    }

    public var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }

    public var sizeDescription: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

/// Metadata for one offline model, as listed by Hugging Face (Legacy
/// `OfflineModelMetadata`). `preferredDownloadFile` ranks MLX first, then
/// GGUF (quantized before full precision), safetensors, then bin.
public struct OfflineModelMetadata: Identifiable, Codable, Sendable {
    public var id: String { modelName }
    public let modelName: String
    public let providerName: String
    public let description: String
    public let modelSize: String
    public let modelSizeBytes: Int64
    public let tags: [String]
    public let downloadCount: Int
    public let modelURL: URL
    public let files: [OfflineModelFile]
    public let isQuantized: Bool

    public init(
        modelName: String, providerName: String, description: String, modelSize: String,
        modelSizeBytes: Int64, tags: [String], downloadCount: Int, modelURL: URL,
        files: [OfflineModelFile], isQuantized: Bool
    ) {
        self.modelName = modelName
        self.providerName = providerName
        self.description = description
        self.modelSize = modelSize
        self.modelSizeBytes = modelSizeBytes
        self.tags = tags
        self.downloadCount = downloadCount
        self.modelURL = modelURL
        self.files = files
        self.isQuantized = isQuantized
    }

    public var preferredDownloadFile: OfflineModelFile? {
        files.sorted {
            let left = Self.priorityScore(for: $0)
            let right = Self.priorityScore(for: $1)
            if left == right { return $0.sizeBytes < $1.sizeBytes }
            return left < right
        }.first
    }

    public static func priorityScore(for file: OfflineModelFile) -> Int {
        let name = file.fileName.lowercased()
        let ext = file.fileExtension
        if name.contains("mlx") || name.contains("ml-ex") { return 0 }
        if ext == "gguf" { return name.contains("q") ? 1 : 2 }
        if ext == "safetensors" { return 3 }
        if ext == "bin" { return 4 }
        return 99
    }
}

/// How capable this machine is at running a local model (Legacy
/// `DeviceTier` / `DeviceCapabilities` / `DeviceCapabilityAnalyzer`).
public enum DeviceTier: String, Sendable {
    case low = "LOW TIER"
    case medium = "MEDIUM TIER"
    case high = "HIGH TIER"
}

public struct DeviceCapabilities: Sendable {
    public let totalRAMGB: Double
    public let availableRAMGB: Double
    public let availableStorageGB: Double
    public let cpuType: String
    public let gpuCapability: String
    public let deviceClass: String
    public let tier: DeviceTier
}

public struct RecommendedOfflineModel: Identifiable, Sendable {
    public var id: String { modelName }
    public let modelName: String
    public let description: String
    public let estimatedSize: String
    public let compatibility: String
    public let suggestedLink: String
}

/// Measures this machine and recommends downloadable models for its tier
/// (Legacy `DeviceCapabilityAnalyzer`). All readings are live
/// (`ProcessInfo`, filesystem free space, machine identifier); the tier
/// thresholds are Legacy's own. Recommendations are named Hugging Face
/// repositories with their real links — the models themselves are fetched
/// live by `HuggingFaceAPI`, never bundled.
public final class DeviceCapabilityAnalyzer: Sendable {
    public static let shared = DeviceCapabilityAnalyzer()
    private init() {}

    public func getCapabilities() -> DeviceCapabilities {
        let totalRAM = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let availableRAM = estimateAvailableRAMGB(totalRAMGB: totalRAM)
        let storage = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64
        let storageGB = Double(storage ?? 0) / 1_073_741_824
        let cpu = machineIdentifier()
        let gpu = inferGPUCapability(totalRAMGB: totalRAM, cpuType: cpu)
        return DeviceCapabilities(
            totalRAMGB: totalRAM, availableRAMGB: availableRAM, availableStorageGB: storageGB,
            cpuType: cpu, gpuCapability: gpu, deviceClass: "Mac", tier: classifyTier(totalRAMGB: totalRAM, availableStorageGB: storageGB, gpuCapability: gpu)
        )
    }

    public func getRecommendedModelList() -> [RecommendedOfflineModel] {
        let capabilities = getCapabilities()
        switch capabilities.tier {
        case .low:
            return [
                RecommendedOfflineModel(
                    modelName: "TinyLlama 1.1B (GGUF)",
                    description: "Compact chat model for fast local responses and low memory usage.",
                    estimatedSize: "~1.1 GB",
                    compatibility: "Optimized for low-memory \(capabilities.deviceClass) devices with \(Int(capabilities.totalRAMGB)) GB RAM.",
                    suggestedLink: "https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF"
                ),
                RecommendedOfflineModel(
                    modelName: "Qwen 2.5 1.5B Instruct",
                    description: "Stronger instruction following while still fitting constrained hardware.",
                    estimatedSize: "~1.6 GB",
                    compatibility: "Good quality for 1B-3B inference on constrained CPU/GPU devices.",
                    suggestedLink: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct"
                ),
            ]
        case .medium:
            return [
                RecommendedOfflineModel(
                    modelName: "Phi-3 Mini 4K Instruct",
                    description: "Balanced model for coding and assistant tasks with moderate RAM usage.",
                    estimatedSize: "~2.2 GB",
                    compatibility: "Balanced 3B model that fits medium-tier RAM and storage budgets.",
                    suggestedLink: "https://huggingface.co/microsoft/phi-3-mini-4k-instruct"
                ),
                RecommendedOfflineModel(
                    modelName: "Llama 3.2 3B Instruct (GGUF)",
                    description: "Reliable mid-size model with solid quality for everyday local use.",
                    estimatedSize: "~3.5 GB",
                    compatibility: "Suitable for medium tier devices with stable quantized performance.",
                    suggestedLink: "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF"
                ),
            ]
        case .high:
            return [
                RecommendedOfflineModel(
                    modelName: "Mistral 7B Instruct (Quantized GGUF)",
                    description: "High-quality reasoning and generation for capable devices.",
                    estimatedSize: "~4.3 GB",
                    compatibility: "High-tier hardware can sustain larger quantized 7B-class models.",
                    suggestedLink: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.2-GGUF"
                ),
                RecommendedOfflineModel(
                    modelName: "Qwen 2.5 7B Instruct",
                    description: "Best quality recommendation with strong multilingual and coding performance.",
                    estimatedSize: "~7.6 GB",
                    compatibility: "Best quality recommendation for high RAM and stronger GPU capability.",
                    suggestedLink: "https://huggingface.co/Qwen/Qwen2.5-7B-Instruct"
                ),
            ]
        }
    }

    private func classifyTier(totalRAMGB: Double, availableStorageGB: Double, gpuCapability: String) -> DeviceTier {
        if totalRAMGB >= 12, availableStorageGB >= 20, gpuCapability == "high" { return .high }
        if totalRAMGB >= 6, availableStorageGB >= 10 { return .medium }
        return .low
    }

    private func estimateAvailableRAMGB(totalRAMGB: Double) -> Double {
        let reserved = max(totalRAMGB * 0.35, 1.5)
        return max(totalRAMGB - reserved, 0)
    }

    private func inferGPUCapability(totalRAMGB: Double, cpuType: String) -> String {
        if cpuType.contains("iPhone") || cpuType.contains("iPad") {
            if totalRAMGB >= 8 { return "high" }
            if totalRAMGB >= 5 { return "medium" }
            return "low"
        }
        if totalRAMGB >= 16 { return "high" }
        if totalRAMGB >= 8 { return "medium" }
        return "low"
    }

    private func machineIdentifier() -> String {
#if canImport(Darwin)
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
#else
        // Linux: the CPU model from /proc/cpuinfo, else the host name.
        if let cpuinfo = try? String(contentsOfFile: "/proc/cpuinfo", encoding: .utf8) {
            for line in cpuinfo.split(separator: "\n") {
                if line.hasPrefix("model name") {
                    return line.split(separator: ":").dropFirst().joined(separator: ":")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return ProcessInfo.processInfo.hostName
#endif
    }
}
