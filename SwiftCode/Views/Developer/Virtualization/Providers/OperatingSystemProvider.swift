import Foundation

public protocol OperatingSystemProvider: Sendable {
    var name: String { get }
    var description: String { get }
    var recommendedCores: Int { get }
    var recommendedMemoryMB: Int { get }
    var recommendedStorageGB: Int { get }
    var downloadSource: String { get }
    var documentationLink: String { get }
    var architectureCompatibility: String { get }
    var supportedImageFormats: [String] { get }
    var installationInstructions: String { get }
    var versions: [String] { get }
}
