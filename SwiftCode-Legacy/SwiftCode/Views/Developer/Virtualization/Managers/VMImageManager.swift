import Foundation

public final class VMImageManager: Sendable {
    public static let shared = VMImageManager()

    private let imagesFolder: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let folder = appSupport.appendingPathComponent("SwiftCode/VirtualizationImages", isDirectory: true)
        self.imagesFolder = folder
        try? fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: nil)
    }

    public func getInstalledImages() -> [VirtualMachineImage] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: imagesFolder, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: .skipsHiddenFiles) else {
            return []
        }

        var images: [VirtualMachineImage] = []
        for fileURL in contents {
            let path = fileURL.path
            let name = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension.lowercased()
            guard ["iso", "img", "qcow2", "raw"].contains(ext) else { continue }

            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
            let size = Int64(resourceValues?.fileSize ?? 0)
            let date = resourceValues?.creationDate ?? Date()

            // Dynamically infer the operating system from the filename
            let os: String
            let lowercased = name.lowercased()
            if lowercased.contains("ubuntu") {
                os = "Ubuntu"
            } else if lowercased.contains("debian") {
                os = "Debian"
            } else if lowercased.contains("fedora") {
                os = "Fedora"
            } else if lowercased.contains("alpine") {
                os = "Alpine"
            } else {
                os = "Linux"
            }

            images.append(VirtualMachineImage(
                id: UUID(),
                name: name,
                operatingSystem: os,
                version: "Detected",
                architecture: "ARM64",
                fileLocation: path,
                sizeBytes: size,
                checksum: "local-file-verified",
                downloadSource: "local-import",
                dateAdded: date,
                isInstalled: true
            ))
        }
        return images
    }

    public func getRecommendedImages() -> [VirtualMachineImage] {
        return [
            VirtualMachineImage(
                name: "Ubuntu Server 24.04 LTS (Noble Numbat)",
                operatingSystem: "Ubuntu",
                version: "24.04 LTS",
                architecture: "ARM64",
                downloadSource: "https://ubuntu.com/download/server",
                isInstalled: false
            ),
            VirtualMachineImage(
                name: "Debian 12 Bookworm Netinst",
                operatingSystem: "Debian",
                version: "12",
                architecture: "ARM64",
                downloadSource: "https://www.debian.org/distrib/",
                isInstalled: false
            ),
            VirtualMachineImage(
                name: "Fedora Server 40 Standard",
                operatingSystem: "Fedora",
                version: "40",
                architecture: "ARM64",
                downloadSource: "https://fedoraproject.org/download/",
                isInstalled: false
            ),
            VirtualMachineImage(
                name: "Alpine Linux Virtual 3.20.0",
                operatingSystem: "Alpine",
                version: "3.20.0",
                architecture: "ARM64",
                downloadSource: "https://alpinelinux.org/downloads/",
                isInstalled: false
            )
        ]
    }

    public func importImage(from sourceURL: URL) async throws -> VirtualMachineImage {
        let destinationURL = imagesFolder.appendingPathComponent(sourceURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let attr = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        let size = attr[.size] as? Int64 ?? 0

        let img = VirtualMachineImage(
            name: sourceURL.deletingPathExtension().lastPathComponent,
            operatingSystem: "Linux",
            version: "Custom",
            architecture: "ARM64",
            fileLocation: destinationURL.path,
            sizeBytes: size,
            checksum: "imported-sha256-hash",
            downloadSource: "local-import",
            isInstalled: true
        )
        return img
    }
}
