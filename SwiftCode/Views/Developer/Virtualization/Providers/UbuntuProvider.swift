import Foundation

public struct UbuntuProvider: OperatingSystemProvider {
    public let name = "Ubuntu"
    public let description = "Recommended Linux environment for general development, supporting swift compile, docker containers, and python scripts."
    public let officialWebsite = "https://ubuntu.com"
    public let officialDocumentation = "https://ubuntu.com/server/docs"
    public let officialDownloadPage = "https://ubuntu.com/download"
    public let supportedArchitectures = "ARM64, x86_64"
    public let recommendedRAM = "8 GB (8192 MB)"
    public let recommendedCPU = "4 Cores"
    public let recommendedStorage = "64 GB"
    public let installationNotes = """
1. Click 'Open Download Page' to download the official Ubuntu Server ARM64 ISO from ubuntu.com.
2. Select the downloaded ISO image file inside our VM Wizard.
3. Configure your allocated resources (we recommend 4 CPU Cores and 8GB RAM).
4. Launch the virtual machine and complete the on-screen Ubuntu server installation steps.
"""

    // Backward compatibility fields
    public let recommendedCores = 4
    public let recommendedMemoryMB = 8192
    public let recommendedStorageGB = 64
    public let downloadSource = "https://ubuntu.com/download"
    public let documentationLink = "https://ubuntu.com/server/docs"
    public let architectureCompatibility = "ARM64, x86_64"
    public let supportedImageFormats = ["ISO", "IMG", "qcow2"]
    public let installationInstructions = """
1. Click 'Open Download Page' to download the official Ubuntu Server ARM64 ISO from ubuntu.com.
2. Select the downloaded ISO image file inside our VM Wizard.
3. Configure your allocated resources (we recommend 4 CPU Cores and 8GB RAM).
4. Launch the virtual machine and complete the on-screen Ubuntu server installation steps.
"""
    public let versions = ["24.04 LTS (Noble Numbat)", "22.04.4 LTS (Jammy Jellyfish)"]

    public init() {}
}
