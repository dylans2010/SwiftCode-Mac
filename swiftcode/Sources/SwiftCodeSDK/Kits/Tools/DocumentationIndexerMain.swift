import Foundation

public enum DocumentationIndexerMain {
    public static func run(arguments: [String]) -> Int32 {
        let path = arguments.first ?? FileManager.default.currentDirectoryPath

        let ws = Workspace(path: path)
        do {
            let files = try ws.fileAccess.listFiles(recursively: true)
            let mdFiles = files.filter { $0.fileName.hasSuffix(".md") }
            print("Indexed \(mdFiles.count) documentation files in \(path)")
            for f in mdFiles {
                print("  - \(f.relativePath) (\(f.sizeInBytes) bytes)")
            }
            return 0
        } catch {
            print("Documentation indexing failed: \(error.localizedDescription)")
            return 1
        }
    }
}
