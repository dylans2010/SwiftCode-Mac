import Foundation
import CryptoKit
import DiagnosticsKit
import WorkspaceKit

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
        let manifest = try JSONDecoder().decode(ExtensionManifest.self, from: manifestData)

        let validator = ExtensionValidator()
        let diags = validator.validate(manifest: manifest, packageRoot: extensionDirectory)
        if diags.contains(where: { $0.severity == .error }) {
            let errorMsg = diags.filter { $0.severity == .error }.map { $0.message }.joined(separator: "; ")
            throw WorkspaceError.writeFailed(outputDirectory, "Extension validation failed: \(errorMsg)")
        }

        let outDir = Workspace(path: outputDirectory)
        try FileManager.default.createDirectory(atPath: outDir.root.normalizedPath, withIntermediateDirectories: true)

        let archiveName = "\(manifest.id)-\(manifest.version).swiftcode-extension"
        let archivePath = outDir.root.appending(archiveName).normalizedPath

        // Remove old archive if exists
        if FileManager.default.fileExists(atPath: archivePath) {
            try FileManager.default.removeItem(atPath: archivePath)
        }

        // Package using zip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = URL(fileURLWithPath: ws.root.normalizedPath)
        process.arguments = ["-r", "-q", "-9", archivePath, "swiftcode.json", "package.json", "dist", "README.md"]
        let errPipe = Pipe()
        process.standardError = errPipe

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 || !FileManager.default.fileExists(atPath: archivePath) {
            // Fallback: zip everything except node_modules and .git
            let fallbackProcess = Process()
            fallbackProcess.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            fallbackProcess.currentDirectoryURL = URL(fileURLWithPath: ws.root.normalizedPath)
            fallbackProcess.arguments = ["-r", "-q", "-9", archivePath, ".", "-x", "*.git*", "-x", "*node_modules*"]
            try fallbackProcess.run()
            fallbackProcess.waitUntilExit()
        }

        guard FileManager.default.fileExists(atPath: archivePath) else {
            throw WorkspaceError.writeFailed(archivePath, "Failed to create extension zip archive")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: archivePath))
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let attrs = try FileManager.default.attributesOfItem(atPath: archivePath)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? Int64(data.count)

        return ExtensionPackageInfo(
            extensionId: manifest.id,
            version: manifest.version,
            packagePath: archivePath,
            archiveSize: size,
            sha256: hash,
            fileCount: 1
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

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-q", packagePath, "-d", tempDir.path]
        try unzip.run()
        unzip.waitUntilExit()

        guard unzip.terminationStatus == 0 else {
            return (false, [Diagnostic(
                code: .projectMalformedStructure,
                severity: .error,
                message: "Failed unzipping package: corrupt archive"
            )])
        }

        let validator = ExtensionValidator()
        let diags = validator.validateFile(at: tempDir.path)
        let hasErrors = diags.contains { $0.severity == .error }
        return (!hasErrors, diags)
    }
}
