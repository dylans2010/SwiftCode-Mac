import Foundation

public final class ProjectSerializer {
    public static let shared = ProjectSerializer()
    private init() {}

    public func serialize(project: Project, to packageURL: URL) async throws {
        // 1. Ensure package structure
        try ProjectPackageManager.shared.createPackageStructure(at: packageURL)

        // 2. Generate and write manifest.json
        var manifest = ManifestProjManager.shared.createInitialManifest(for: project)

        // 3. Generate and write metadata.json
        let metadata = ProjectMetadataManager.shared.generateMetadata(for: project)
        let metadataData = try ProjectJSONManager.shared.encode(metadata)
        try ProjectFileManager.shared.writeFile(data: metadataData, to: packageURL.appendingPathComponent("metadata.json"))

        // 4. project.json (Codable model)
        let projectData = try ProjectJSONManager.shared.encode(project)
        try ProjectFileManager.shared.writeFile(data: projectData, to: packageURL.appendingPathComponent("project.json"))

        // 5. project.xml
        let projectXML = try ProjectXMLManager.shared.encode(project)
        try ProjectFileManager.shared.writeFile(data: projectXML, to: packageURL.appendingPathComponent("project.xml"))

        // 6. project.plist
        let projectPlist = try ProjectPlistManager.shared.encode(project)
        try ProjectFileManager.shared.writeFile(data: projectPlist, to: packageURL.appendingPathComponent("project.plist"))

        // 7. version.json
        let versionData = try ProjectJSONManager.shared.encode(["schemaVersion": ProjectVersionManager.shared.currentSchemaVersion])
        try ProjectFileManager.shared.writeFile(data: versionData, to: packageURL.appendingPathComponent("version.json"))

        // 8. Sources/ Assets/ Resources/ (Copy files)
        try await copyFiles(from: project, to: packageURL)

        // 9. integrity.json & hash.json
        try generateHashes(at: packageURL, manifest: &manifest)

        // 10. Write manifest.json (finally, with hashes)
        let manifestData = try ProjectJSONManager.shared.encode(manifest)
        try ProjectFileManager.shared.writeFile(data: manifestData, to: packageURL.appendingPathComponent("manifest.json"))

        // Update manifest hash in integrity.json
        let manifestHash = ProjectHashManager.shared.hash(data: manifestData)
        let integrityData = try ProjectJSONManager.shared.encode(["manifestHash": manifestHash])
        try ProjectFileManager.shared.writeFile(data: integrityData, to: packageURL.appendingPathComponent("integrity.json"))
    }

    private func copyFiles(from project: Project, to packageURL: URL) async throws {
        let sourcesDir = packageURL.appendingPathComponent("Sources")
        let projectDir = await project.directoryURL

        // Ensure source directory exists before trying to list its contents
        guard FileManager.default.fileExists(atPath: projectDir.path) else { return }

        // Use FileManager to copy contents from project directory to Sources/ within package
        let contents = try FileManager.default.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for item in contents {
            if item.lastPathComponent == "project.json" { continue }
            let dest = sourcesDir.appendingPathComponent(item.lastPathComponent)
            try ProjectFileManager.shared.copyItem(at: item, to: dest)
        }
    }

    private func generateHashes(at packageURL: URL, manifest: inout ProjectManifest) throws {
        let fm = FileManager.default
        var totalHash = ""

        // Walk through the package and hash files
        if let enumerator = fm.enumerator(at: packageURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isFile && fileURL.lastPathComponent != "manifest.json" && fileURL.lastPathComponent != "integrity.json" {
                    let fileHash = try ProjectHashManager.shared.hashFile(at: fileURL)
                    totalHash += fileHash
                }
            }
        }

        if !totalHash.isEmpty {
            let finalHash = ProjectHashManager.shared.hash(data: totalHash.data(using: .utf8)!)
            manifest.security.packageIntegrityHash = finalHash
        }
    }
}
