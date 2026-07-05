import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum DeviceTier: String {
    case low = "LOW TIER"
    case medium = "MEDIUM TIER"
    case high = "HIGH TIER"
}

struct DeviceCapabilities {
    let totalRAMGB: Double
    let availableRAMGB: Double
    let availableStorageGB: Double
    let cpuType: String
    let gpuCapability: String
    let deviceClass: String
    let tier: DeviceTier
}

struct RecommendedOfflineModel: Identifiable {
    var id: String { modelName }
    let modelName: String
    let description: String
    let estimatedSize: String
    let compatibility: String
    let suggestedLink: String
}

final class DeviceCapabilityAnalyzer {
    static let shared = DeviceCapabilityAnalyzer()
    private init() {}

    func getCapabilities() -> DeviceCapabilities {
        let totalRAM = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let availableRAM = estimateAvailableRAMGB(totalRAMGB: totalRAM)
        let storage = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())[.systemFreeSize] as? Int64
        let storageGB = Double(storage ?? 0) / 1_073_741_824

        let cpu = machineIdentifier()
        let gpu = inferGPUCapability(totalRAMGB: totalRAM, cpuType: cpu)
        let deviceClass = inferDeviceClass()

        return DeviceCapabilities(
            totalRAMGB: totalRAM,
            availableRAMGB: availableRAM,
            availableStorageGB: storageGB,
            cpuType: cpu,
            gpuCapability: gpu,
            deviceClass: deviceClass,
            tier: classifyTier(totalRAMGB: totalRAM, availableStorageGB: storageGB, gpuCapability: gpu)
        )
    }

    func getRecommendedModelList() -> [RecommendedOfflineModel] {
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
                )
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
                )
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
                )
            ]
        }
    }

    private func classifyTier(totalRAMGB: Double, availableStorageGB: Double, gpuCapability: String) -> DeviceTier {
        if totalRAMGB >= 12, availableStorageGB >= 20, gpuCapability == "high" {
            return .high
        }

        if totalRAMGB >= 6, availableStorageGB >= 10 {
            return .medium
        }

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

    private func inferDeviceClass() -> String {
        #if canImport(UIKit)
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return "iPhone"
        case .pad:
            return "iPad"
        default:
            return "Apple Device"
        }
        #else
        return "Apple Device"
        #endif
    }

    private func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
    }
}
