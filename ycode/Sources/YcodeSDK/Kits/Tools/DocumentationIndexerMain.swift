import Foundation

/// `documentation-indexer` tool (Legacy `Sources/Tools/DocumentationIndexer/main.swift`).
///
/// Lists every Markdown file under a directory. No network, no index file
/// is written — Legacy only printed the inventory, and so does this port.
/// Library entry point: the executable target wraps it in a thin `@main`
/// that calls `exit(DocumentationIndexerMain.run(...))`.
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
