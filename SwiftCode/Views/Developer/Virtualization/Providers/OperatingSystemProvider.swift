import Foundation

public protocol OperatingSystemProvider: Sendable {
    var name: String { get }
    var description: String { get }
    var officialWebsite: String { get }
    var officialDocumentation: String { get }
    var officialDownloadPage: String { get }
    var supportedArchitectures: String { get }
    var recommendedRAM: String { get }
    var recommendedCPU: String { get }
    var recommendedStorage: String { get }
    var installationNotes: String { get }

    // Detailed resource metadata
    var releaseNotes: String { get }
    var minimumRequirements: String { get }
    var packageManagerGuide: String { get }
    var gettingStartedGuide: String { get }
    var securityAdvisories: String { get }
    var communityResources: String { get }

    // Backward compatibility & raw specifications
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
