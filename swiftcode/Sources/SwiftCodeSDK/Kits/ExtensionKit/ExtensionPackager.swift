import Foundation
import YcodeAssistant
import SwiftCodeExtensions
import YcodeSubprocess

public struct ExtensionPackageInfo: Sendable, Codable {
    public let extensionId: String
    public let version: String
    public let packagePath: String
    public let archiveSize: Int64
    public let sha256: String
    public let fileCount: Int

    public init(
        extensionId: String,
        version: String,
        packagePath: String,
        archiveSize: Int64,
        sha256: String,
        fileCount: Int
    ) {
        self.extensionId = extensionId
        self.version = version
        self.packagePath = packagePath
        self.archiveSize = archiveSize
        self.sha256 = sha256
        self.fileCount = fileCount
    }
}

public final class ExtensionPackager: Sendable {
    public init() {}

    public func package(extensionDirectory: String, outputDirectory: String) throws -> ExtensionPackageInfo {
        let ws = Workspace(path: extensionDirectory)
        let manifestData = try ws.fileAccess.readFile(at: "swiftcode.json")

        let validator = SDKManifestValidator()
        let diags = validator.validate(data: manifestData, packageRoot: extensionDirectory)
        if diags.contains(where: { $0.severity == .error }) {
            let errorMsg = diags.filter { $0.severity == .error }.map { $0.message }.joined(separator: "; ")
            throw WorkspaceError.writeFailed(outputDirectory, "Extension validation failed: \(errorMsg)")
        }
        let manifest = try validator.validateAndDecode(data: manifestData)

        let outDir = Workspace(path: outputDirectory)
        try FileManager.default.createDirectory(atPath: outDir.root.normalizedPath, withIntermediateDirectories: true)

        let archiveName = "\(manifest.id)-\(manifest.version).swiftcode-extension"
        let archivePath = outDir.root.appending(archiveName).normalizedPath

        if FileManager.default.fileExists(atPath: archivePath) {
            try FileManager.default.removeItem(atPath: archivePath)
        }

        let zipOutput = try Subprocess.run(
            "/usr/bin/zip",
            ["-r", "-q", "-9", archivePath, "swiftcode.json", "package.json", "dist", "README.md"],
            currentDirectory: URL(fileURLWithPath: ws.root.normalizedPath)
        )

        if zipOutput.status != 0 || !FileManager.default.fileExists(atPath: archivePath) {
            _ = try Subprocess.run(
                "/usr/bin/zip",
                ["-r", "-q", "-9", archivePath, ".", "-x", "*.git*", "-x", "*node_modules*"],
                currentDirectory: URL(fileURLWithPath: ws.root.normalizedPath)
            )
        }

        guard FileManager.default.fileExists(atPath: archivePath) else {
            throw WorkspaceError.writeFailed(archivePath, "Failed to create extension zip archive")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: archivePath))
        let hash = SHA256.hash(data).map { String(format: "%02x", $0) }.joined()
        let attrs = try FileManager.default.attributesOfItem(atPath: archivePath)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? Int64(data.count)
        let fileCount = try packagedFileCount(in: ws)

        return ExtensionPackageInfo(
            extensionId: manifest.id,
            version: manifest.version,
            packagePath: archivePath,
            archiveSize: size,
            sha256: hash,
            fileCount: fileCount
        )
    }

    public func verify(packagePath: String) throws -> (isValid: Bool, diagnostics: [Diagnostic]) {
        guard FileManager.default.fileExists(atPath: packagePath) else {
            return (false, [Diagnostic(
                code: .projectNotFound,
                severity: .error,
                message: "Package archive not found at: \(packagePath)"
            )])
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("verify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let unzip = try Subprocess.run("/usr/bin/unzip", ["-q", packagePath, "-d", tempDir.path])

        guard unzip.status == 0 else {
            return (false, [Diagnostic(
                code: .projectMalformedStructure,
                severity: .error,
                message: "Failed unzipping package: corrupt archive"
            )])
        }

        let validator = SDKManifestValidator()
        let diags = validator.validateFile(at: tempDir.path)
        let hasErrors = diags.contains { $0.severity == .error }
        return (!hasErrors, diags)
    }

    private func packagedFileCount(in ws: Workspace) throws -> Int {
        let fm = FileManager.default
        var count = 0
        for name in ["swiftcode.json", "package.json", "README.md"] where ws.fileAccess.exists(at: name) {
            count += 1
        }
        let dist = ws.root.appending("dist")
        if fm.fileExists(atPath: dist.normalizedPath),
           let enumerator = fm.enumerator(atPath: dist.normalizedPath) {
            for case let entry as String in enumerator where !entry.hasPrefix(".") {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: dist.appending(entry).normalizedPath, isDirectory: &isDir), !isDir.boolValue {
                    count += 1
                }
            }
        }
        if count == 0 {
            count = try ws.fileAccess.listFiles(recursively: true)
                .filter { !$0.isDirectory && !$0.relativePath.hasPrefix(".git") && !$0.relativePath.contains("node_modules") }
                .count
        }
        return count
    }
}
