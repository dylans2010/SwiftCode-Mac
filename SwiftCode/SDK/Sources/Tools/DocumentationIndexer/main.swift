import Foundation
import SwiftCodeSDK

let args = Array(CommandLine.arguments.dropFirst())
let path = args.first ?? FileManager.default.currentDirectoryPath

let ws = Workspace(path: path)
do {
    let files = try ws.fileAccess.listFiles(recursively: true)
    let mdFiles = files.filter { $0.fileName.hasSuffix(".md") }
    print("Indexed \(mdFiles.count) documentation files in \(path)")
    for f in mdFiles {
        print("  - \(f.relativePath) (\(f.sizeInBytes) bytes)")
    }
    exit(0)
} catch {
    print("Documentation indexing failed: \(error.localizedDescription)")
    exit(1)
}
