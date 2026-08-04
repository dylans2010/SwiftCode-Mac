import Foundation

public struct FedoraProvider: OperatingSystemProvider {
    public let name = "Fedora"
    public let description = "Up-to-date and cutting edge Linux workstation environment. Excellent choice for modern web, cloud-native and server development."
    public let officialWebsite = "https://fedoraproject.org"
    public let officialDocumentation = "https://docs.fedoraproject.org"
    public let officialDownloadPage = "https://fedoraproject.org/download"
    public let supportedArchitectures = "ARM64, x86_64"
    public let recommendedRAM = "8 GB (8192 MB)"
    public let recommendedCPU = "4 Cores"
    public let recommendedStorage = "50 GB"
    public let installationNotes = """
1. Open the Fedora download directory.
2. Select the Fedora Server ARM64 ISO and download it locally.
3. Import the ISO inside the SwiftCode Virtualization wizard.
4. Mount your local projects directory, run the VM, and install the workstation operating system.
"""

    // Backward compatibility fields
    public let recommendedCores = 4
    public let recommendedMemoryMB = 8192
    public let recommendedStorageGB = 50
    public let downloadSource = "https://fedoraproject.org/download"
    public let documentationLink = "https://docs.fedoraproject.org"
    public let architectureCompatibility = "ARM64, x86_64"
    public let supportedImageFormats = ["ISO", "qcow2"]
    public let installationInstructions = """
1. Open the Fedora download directory.
2. Select the Fedora Server ARM64 ISO and download it locally.
3. Import the ISO inside the SwiftCode Virtualization wizard.
4. Mount your local projects directory, run the VM, and install the workstation operating system.
"""
    public let versions = ["Fedora 40", "Fedora 39"]

    public init() {}
}
