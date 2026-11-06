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

    // Expanded protocol metadata
    public let releaseNotes = "Ubuntu 24.04 LTS delivers optimized performance, increased security, and 12 years of security updates via Ubuntu Pro. Includes modern developer toolchains: Python 3.12, Go 1.22, Rust 1.75."
    public let minimumRequirements = "CPU: 2 Cores (64-bit) • Memory: 4 GB RAM • Storage: 25 GB free disk space."
    public let packageManagerGuide = "APT (Advanced Package Tool). Install packages using: `sudo apt update && sudo apt install <package-name>`. Search for packages using: `apt search <query>`."
    public let gettingStartedGuide = "Log in using the configured user. Enable SSH daemon using `sudo systemctl enable --now ssh`. Map ports to standard host endpoints to access backend servers."
    public let securityAdvisories = "Track official security updates at: https://ubuntu.com/security/notices. Automatic security patching can be enabled with unattended-upgrades."
    public let communityResources = "Ask Ubuntu forums: https://askubuntu.com. Canonical official support: https://ubuntu.com/support."

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
