import Foundation

public struct DebianProvider: OperatingSystemProvider {
    public let name = "Debian"
    public let description = "Highly stable and lightweight distribution. Ideal for production-parity backend containers and testing."
    public let officialWebsite = "https://www.debian.org"
    public let officialDocumentation = "https://www.debian.org/doc"
    public let officialDownloadPage = "https://www.debian.org/distrib"
    public let supportedArchitectures = "ARM64, x86_64, i386"
    public let recommendedRAM = "4 GB (4096 MB)"
    public let recommendedCPU = "2 Cores"
    public let recommendedStorage = "40 GB"
    public let installationNotes = """
1. Navigate to debian.org using 'Open Download Page' and download the Netinst ARM64 ISO.
2. Provide the ISO file path in Step 2 of our VM Creation Wizard.
3. Configure allocated hardware specs (we recommend 2 Cores and 4GB RAM).
4. Launch the console window, select the standard graphical or text installer, and proceed with setup.
"""

    // Backward compatibility fields
    public let recommendedCores = 2
    public let recommendedMemoryMB = 4096
    public let recommendedStorageGB = 40
    public let downloadSource = "https://www.debian.org/distrib"
    public let documentationLink = "https://www.debian.org/doc"
    public let architectureCompatibility = "ARM64, x86_64, i386"
    public let supportedImageFormats = ["ISO", "raw"]
    public let installationInstructions = """
1. Navigate to debian.org using 'Open Download Page' and download the Netinst ARM64 ISO.
2. Provide the ISO file path in Step 2 of our VM Creation Wizard.
3. Configure allocated hardware specs (we recommend 2 Cores and 4GB RAM).
4. Launch the console window, select the standard graphical or text installer, and proceed with setup.
"""
    public let versions = ["Debian 12 (Bookworm)", "Debian 11 (Bullseye)"]

    public init() {}
}
