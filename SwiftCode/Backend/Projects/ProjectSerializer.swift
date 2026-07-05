import Foundation
import CryptoKit

struct SerializedProjectPackage: Codable {
    let project: Project
    let permission: TransferPermission
    let fileEntries: [ProjectFileEntry]
    let checksum: String
    let createdAt: Date
}

struct ProjectFileEntry: Codable, Hashable {
    let relativePath: String
    let data: Data
    let isDirectory: Bool
}

enum ProjectSerializationError: LocalizedError {
    case checksumMismatch
    case corruptedArchive

    var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Transferred project failed integrity validation."
        case .corruptedArchive:
            return "The transfer payload is corrupted."
        }
    }
}

struct ProjectSerializer {
    @MainActor
    func serialize(project: Project, permission: TransferPermission) throws -> Data {
        let root = project.directoryURL
        let fileEntries = try collectEntries(from: root, relativeTo: root)
        let checksum = sha256(for: fileEntries)
        let package = SerializedProjectPackage(project: project, permission: permission, fileEntries: fileEntries, checksum: checksum, createdAt: Date())
        return try JSONEncoder().encode(package)
    }

    func deserialize(_ data: Data) throws -> SerializedProjectPackage {
        let package = try JSONDecoder().decode(SerializedProjectPackage.self, from: data)
        let checksum = sha256(for: package.fileEntries)
        guard checksum == package.checksum else {
            throw ProjectSerializationError.checksumMismatch
        }
        return package
    }

    private func collectEntries(from directory: URL, relativeTo base: URL) throws -> [ProjectFileEntry] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw ProjectSerializationError.corruptedArchive
        }
        var entries: [ProjectFileEntry] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let relativePath = url.path.replacingOccurrences(of: base.path + "/", with: "")
            if relativePath == "project.json" { continue }
            if values.isDirectory == true {
                entries.append(ProjectFileEntry(relativePath: relativePath, data: Data(), isDirectory: true))
            } else {
                entries.append(ProjectFileEntry(relativePath: relativePath, data: try Data(contentsOf: url), isDirectory: false))
            }
        }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    private func sha256(for entries: [ProjectFileEntry]) -> String {
        let digest = SHA256.hash(data: entries.reduce(into: Data()) { partial, entry in
            partial.append(entry.relativePath.data(using: .utf8) ?? Data())
            partial.append(entry.data)
        })
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
}
