import Foundation

public struct AssistSnapshotFunctions {
    private static let fileManager = FileManager.default

    public static func createSnapshot(project: URL, message: String) throws -> URL {
        let snapshotsDir = try getSnapshotsDirectory()
        let snapshotId = UUID().uuidString
        let snapshotURL = snapshotsDir.appendingPathComponent(snapshotId)

        try fileManager.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
        try fileManager.copyItem(at: project, to: snapshotURL.appendingPathComponent("files"))

        // Save metadata
        let metadata = AssistSnapshotMetadata(id: snapshotId, timestamp: Date(), message: message, rootPath: project.path)
        let metadataData = try JSONEncoder().encode(metadata)
        try metadataData.write(to: snapshotURL.appendingPathComponent("metadata.json"))

        return snapshotURL
    }

    public static func restoreSnapshot(id: String, to project: URL) throws {
        let snapshotsDir = try getSnapshotsDirectory()
        let snapshotURL = snapshotsDir.appendingPathComponent(id)
        let filesURL = snapshotURL.appendingPathComponent("files")

        guard fileManager.fileExists(atPath: filesURL.path) else {
            throw NSError(domain: "AssistSnapshot", code: 404, userInfo: [NSLocalizedDescriptionKey: "Snapshot '\(id)' not found."])
        }

        // Clean current project
        let contents = try fileManager.contentsOfDirectory(at: project, includingPropertiesForKeys: nil)
        for url in contents {
            try fileManager.removeItem(at: url)
        }

        // Restore files
        let restoredContents = try fileManager.contentsOfDirectory(at: filesURL, includingPropertiesForKeys: nil)
        for url in restoredContents {
            try fileManager.copyItem(at: url, to: project.appendingPathComponent(url.lastPathComponent))
        }
    }

    public static func listSnapshots() throws -> [AssistSnapshotMetadata] {
        let snapshotsDir = try getSnapshotsDirectory()
        let contents = try fileManager.contentsOfDirectory(at: snapshotsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

        var snapshots: [AssistSnapshotMetadata] = []
        for url in contents {
            let metaURL = url.appendingPathComponent("metadata.json")
            if let data = try? Data(contentsOf: metaURL), let meta = try? JSONDecoder().decode(AssistSnapshotMetadata.self, from: data) {
                snapshots.append(meta)
            }
        }
        return snapshots.sorted(by: { $0.timestamp > $1.timestamp })
    }

    public static func compare(project: URL, withSnapshot id: String) throws -> [AssistFileDiff] {
        let snapshotsDir = try getSnapshotsDirectory()
        let snapshotFilesURL = snapshotsDir.appendingPathComponent(id).appendingPathComponent("files")

        guard fileManager.fileExists(atPath: snapshotFilesURL.path) else { return [] }

        var diffs: [AssistFileDiff] = []

        let projectFiles = try fileManager.subpathsOfDirectory(atPath: project.path)
        let snapshotFiles = try fileManager.subpathsOfDirectory(atPath: snapshotFilesURL.path)

        let allPaths = Set(projectFiles).union(Set(snapshotFiles))

        for path in allPaths {
            let projectFileURL = project.appendingPathComponent(path)
            let snapshotFileURL = snapshotFilesURL.appendingPathComponent(path)

            let projectExists = fileManager.fileExists(atPath: projectFileURL.path)
            let snapshotExists = fileManager.fileExists(atPath: snapshotFileURL.path)

            if projectExists && !snapshotExists {
                diffs.append(AssistFileDiff(path: path, status: .added, changes: "File added"))
            } else if !projectExists && snapshotExists {
                diffs.append(AssistFileDiff(path: path, status: .deleted, changes: "File deleted"))
            } else {
                // Both exist, compare contents
                let projectContent = try? String(contentsOf: projectFileURL, encoding: .utf8)
                let snapshotContent = try? String(contentsOf: snapshotFileURL, encoding: .utf8)

                if projectContent != snapshotContent {
                    diffs.append(AssistFileDiff(path: path, status: .modified, changes: "Content changed"))
                }
            }
        }

        return diffs
    }

    private static func getSnapshotsDirectory() throws -> URL {
        let appSupport = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let snapshotsDir = appSupport.appendingPathComponent("AssistSnapshots")
        if !fileManager.fileExists(atPath: snapshotsDir.path) {
            try fileManager.createDirectory(at: snapshotsDir, withIntermediateDirectories: true)
        }
        return snapshotsDir
    }
}
