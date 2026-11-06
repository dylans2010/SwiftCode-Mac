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

    // Expanded protocol metadata
    public let releaseNotes = "Debian 12 'Bookworm' includes Linux Kernel 6.1, native systemd updates, and robust cryptographic libraries. Features packages such as LLVM/Clang, GCC 12.2, and system libraries ideal for low-level backend integration."
    public let minimumRequirements = "CPU: 1 Core • Memory: 1 GB RAM • Storage: 10 GB free disk space."
    public let packageManagerGuide = "APT (Advanced Package Tool). Install packages using: `sudo apt-get update && sudo apt-get install <package>`. Unpack local archives using `dpkg -i <file.deb>`."
    public let gettingStartedGuide = "Log in under root or standard user. Configure non-free repositories if extra firmware drivers are needed. Enable system daemon logs via journalctl."
    public let securityAdvisories = "Review official security bulletins at: https://www.debian.org/security/. Patches are maintained strictly by the Debian Security Team."
    public let communityResources = "Debian User Forums: https://forums.debian.net/. Mailing lists: https://lists.debian.org/."

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
