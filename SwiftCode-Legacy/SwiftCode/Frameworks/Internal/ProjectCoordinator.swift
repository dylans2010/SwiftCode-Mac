import Foundation
import ZIPFoundation

public final class ProjectCoordinator: Sendable {
    public static let shared = ProjectCoordinator()
    private init() {}

    public func exportProject(_ project: Project, to destinationURL: URL) async throws {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let packageTempDir = tempDir.appendingPathComponent(project.name + ".scproj_payload")
        try fm.createDirectory(at: packageTempDir, withIntermediateDirectories: true)

        // 1. Serialize into temporary folder
        try await ProjectSerializer.shared.serialize(project: project, to: packageTempDir)

        // Remove destination if it exists
        try? fm.removeItem(at: destinationURL)

        // 2. Zip the folder to destinationURL
        try fm.zipItem(at: packageTempDir, to: destinationURL)

        // Cleanup tempDir
        try? fm.removeItem(at: tempDir)
    }

    public func importProject(from packageURL: URL) async throws -> Project {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let fileExists = fm.fileExists(atPath: packageURL.path, isDirectory: &isDir)

        var workingDir = packageURL
        var isTempDir = false
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        if fileExists && !isDir.boolValue {
            // It's a single file zipped archive. Let's unpack it to a temp folder!
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try fm.unzipItem(at: packageURL, to: tempDir)
            workingDir = tempDir
            isTempDir = true
        }

        defer {
            if isTempDir {
                try? fm.removeItem(at: tempDir)
            }
        }

        // 1. Deserialize from the unzipped files / working dir
        var project = try ProjectDeserializer.shared.deserialize(from: workingDir)

        // 2. Move/restore project files into the user's projects directory
        let projectsRoot = await MainActor.run { CodingManager.shared.projectsRoot }
        let sanitizedName = project.name
        var finalName = sanitizedName
        var destDir = projectsRoot.appendingPathComponent(finalName)
        var counter = 2
        while fm.fileExists(atPath: destDir.path) {
            finalName = "\(sanitizedName) \(counter)"
            destDir = projectsRoot.appendingPathComponent(finalName)
            counter += 1
        }

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(at: workingDir, includingPropertiesForKeys: nil)
        for item in contents {
            let destItem = destDir.appendingPathComponent(item.lastPathComponent)
            try fm.copyItem(at: item, to: destItem)
        }

        // Align name & custom path
        project.name = finalName
        project.customDirectoryPath = nil

        // Overwrite/update project.json in the destination folder
        let projectData = try ProjectJSONManager.shared.encode(project)
        try ProjectFileManager.shared.writeFile(data: projectData, to: destDir.appendingPathComponent("project.json"))

        return project
    }

    public func validateProject(at packageURL: URL) throws {
        try ProjectValidator.shared.validate(packageURL: packageURL)
    }

    public func getManifest(for packageURL: URL) throws -> ProjectManifest {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        if fm.fileExists(atPath: packageURL.path, isDirectory: &isDir) && !isDir.boolValue {
            let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: tempDir) }

            try fm.unzipItem(at: packageURL, to: tempDir)
            let manifestURL = tempDir.appendingPathComponent("manifest.json")
            let data = try ProjectFileManager.shared.readFile(at: manifestURL)
            return try ProjectJSONManager.shared.decode(ProjectManifest.self, from: data)
        }

        let manifestURL = packageURL.appendingPathComponent("manifest.json")
        let data = try ProjectFileManager.shared.readFile(at: manifestURL)
        return try ProjectJSONManager.shared.decode(ProjectManifest.self, from: data)
    }
}
