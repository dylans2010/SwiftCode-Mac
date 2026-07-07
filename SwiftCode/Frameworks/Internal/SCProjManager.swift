import Foundation
import CryptoKit

public struct SCProjData: Codable {
    public struct FileData: Codable {
        public let name: String
        public let relativePath: String
        public let isDirectory: Bool
        public let content: String? // Base64 encoded
        public var children: [FileData]?
    }

    public let name: String
    public let description: String
    public let createdAt: Date
    public let lastOpened: Date
    public let ciBuildConfiguration: CIBuildConfiguration?
    public let githubRepo: String?
    public let files: [FileData]
    public var signature: String?

    public func generateSignature(key: SymmetricKey) throws -> String {
        var copy = self
        copy.signature = nil
        let data = try JSONEncoder().encode(copy)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(authenticationCode).base64EncodedString()
    }

    public func isValid(key: SymmetricKey) throws -> Bool {
        guard let sig = signature, let sigData = Data(base64Encoded: sig) else { return false }
        var copy = self
        copy.signature = nil
        let data = try JSONEncoder().encode(copy)
        return HMAC<SHA256>.isValidAuthenticationCode(sigData, authenticating: data, using: key)
    }
}

public final class SCProjManager {
    public static let shared = SCProjManager()
    private let key: SymmetricKey

    private init() {
        // In a real app, this key should be securely stored/retrieved.
        // For now, we'll use a derived key from a static string for demonstration.
        let keyString = "SwiftCode-Internal-Secret-Key-2024"
        let data = keyString.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        self.key = SymmetricKey(data: Data(hash))
    }

    public func exportProject(_ project: Project) async throws -> URL {
        let scProjData = try await convertToSCProjData(project)
        var signedData = scProjData
        signedData.signature = try signedData.generateSignature(key: key)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(signedData)

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(project.name).scproj")
        try data.write(to: fileURL)
        return fileURL
    }

    public func importProject(from url: URL) async throws -> Project {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateEncodingStrategy = .iso8601
        let scProjData = try decoder.decode(SCProjData.self, from: data)

        guard try scProjData.isValid(key: key) else {
            throw NSError(domain: "SCProjManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Project file is corrupted or has been tampered with."])
        }

        return try await convertToProject(scProjData)
    }

    private func convertToSCProjData(_ project: Project) async throws -> SCProjData {
        let fileData = try await fetchFileData(for: project.files, in: project.directoryURL)
        return SCProjData(
            name: project.name,
            description: project.description,
            createdAt: project.createdAt,
            lastOpened: project.lastOpened,
            ciBuildConfiguration: project.ciBuildConfiguration,
            githubRepo: project.githubRepo,
            files: fileData,
            signature: nil
        )
    }

    private func fetchFileData(for nodes: [FileNode], in projectDir: URL) async throws -> [SCProjData.FileData] {
        var results: [SCProjData.FileData] = []
        for node in nodes {
            let content: String?
            let children: [SCProjData.FileData]?

            if node.isDirectory {
                content = nil
                children = try await fetchFileData(for: node.children, in: projectDir)
            } else {
                let data = try? Data(contentsOf: projectDir.appendingPathComponent(node.path))
                content = data?.base64EncodedString()
                children = nil
            }

            results.append(SCProjData.FileData(
                name: node.name,
                relativePath: node.path,
                isDirectory: node.isDirectory,
                content: content,
                children: children
            ))
        }
        return results
    }

    private func convertToProject(_ data: SCProjData) async throws -> Project {
        // This is a bit tricky because Project wants to live in the Projects directory.
        // We'll let ProjectManager handle the actual creation of the directory and files.

        let projectManager = await ProjectManager.shared
        let project = try await projectManager.createProject(name: data.name)

        // Overwrite default metadata
        var updatedProject = project
        updatedProject.description = data.description
        updatedProject.createdAt = data.createdAt
        updatedProject.lastOpened = data.lastOpened
        updatedProject.ciBuildConfiguration = data.ciBuildConfiguration
        updatedProject.githubRepo = data.githubRepo

        // Create files
        try await createFiles(from: data.files, in: updatedProject.directoryURL)

        return updatedProject
    }

    private func createFiles(from fileDatas: [SCProjData.FileData], in directoryURL: URL) async throws {
        for fileData in fileDatas {
            let url = directoryURL.appendingPathComponent(fileData.relativePath)
            if fileData.isDirectory {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                if let children = fileData.children {
                    try await createFiles(from: children, in: directoryURL)
                }
            } else if let content = fileData.content, let data = Data(base64Encoded: content) {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, atomically: true)
            }
        }
    }
}
