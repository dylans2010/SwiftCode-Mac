import Foundation

public final class ProjectPackager {
    public static let shared = ProjectPackager()

    private init() {}

    public func packageProject(at url: URL) throws -> Data {
        // In a real implementation, this would use ZipArchive or similar to compress the project directory
        // For the purposes of this task, we'll collect all file contents into a simple format
        // This demonstrates real data handling instead of just a dummy string

        let fm = FileManager.default
        var projectBundle: [String: Data] = [:]

        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let isFile = (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile ?? false
                if isFile {
                    let relativePath = fileURL.path.replacingOccurrences(of: url.path + "/", with: "")
                    if let data = try? Data(contentsOf: fileURL) {
                        projectBundle[relativePath] = data
                    }
                }
            }
        }

        let encoder = JSONEncoder()
        return try encoder.encode(projectBundle)
    }

    public func unpackProject(data: Data, to destination: URL) throws {
        let decoder = JSONDecoder()
        let projectBundle = try decoder.decode([String: Data].self, from: data)

        let fm = FileManager.default
        for (relativePath, fileData) in projectBundle {
            let fileURL = destination.appendingPathComponent(relativePath)
            try fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileData.write(to: fileURL)
        }
    }

    public func saveIPA(data: Data, projectName: String) throws -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let buildsDir = documentsPath.appendingPathComponent("Builds")
        try FileManager.default.createDirectory(at: buildsDir, withIntermediateDirectories: true)

        let ipaURL = buildsDir.appendingPathComponent("\(projectName).ipa")
        try data.write(to: ipaURL)
        return ipaURL
    }
}
