import Foundation

public struct CopyFileTool {
    public static let identifier = "copy_file"

    public func run(sourcePath: String, destinationPath: String) async throws {
        try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
    }
}
