import Foundation

public struct AlpineProvider: OperatingSystemProvider {
    public let name = "Alpine"
    public let description = "Super-lightweight and security-oriented Linux. Boots in milliseconds and uses minimal resources (less than 100MB RAM idle)."
    public let officialWebsite = "https://alpinelinux.org"
    public let officialDocumentation = "https://wiki.alpinelinux.org"
    public let officialDownloadPage = "https://alpinelinux.org/downloads/"
    public let supportedArchitectures = "ARM64, x86_64, x86, ARMHF"
    public let recommendedRAM = "1 GB (1024 MB)"
    public let recommendedCPU = "1 Core"
    public let recommendedStorage = "10 GB"
    public let installationNotes = """
1. Open alpine.org downloads and fetch the Virtual ARM64 ISO (minimal size, around 50MB).
2. Configure the VM with 1 Core and 1GB RAM (or even 512MB).
3. Start the console session, log in as root (no password), and run `setup-alpine` to configure.
4. Enjoy your super-fast developer shell environment.
"""

    // Backward compatibility fields
    public let recommendedCores = 1
    public let recommendedMemoryMB = 1024
    public let recommendedStorageGB = 10
    public let downloadSource = "https://alpinelinux.org/downloads/"
    public let documentationLink = "https://wiki.alpinelinux.org/"
    public let architectureCompatibility = "ARM64, x86_64, x86, ARMHF"
    public let supportedImageFormats = ["ISO", "TAR.GZ"]
    public let installationInstructions = """
1. Open alpine.org downloads and fetch the Virtual ARM64 ISO (minimal size, around 50MB).
2. Configure the VM with 1 Core and 1GB RAM (or even 512MB).
3. Start the console session, log in as root (no password), and run `setup-alpine` to configure.
4. Enjoy your super-fast developer shell environment.
"""
    public let versions = ["3.20.0", "3.19.2"]

    public init() {}
}
