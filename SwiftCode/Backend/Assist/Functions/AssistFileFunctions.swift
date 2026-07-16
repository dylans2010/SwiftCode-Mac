import Foundation

public struct AssistFileFunctions {
    private static let fileManager = FileManager.default

    public static func readFile(at url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func writeFile(at url: URL, content: String) throws {
        let parentDir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentDir.path) {
            try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func appendToFile(at url: URL, content: String) throws {
        if let fileHandle = try? FileHandle(forWritingTo: url) {
            defer { try? fileHandle.close() }
            try fileHandle.seekToEnd()
            if let data = content.data(using: .utf8) {
                try fileHandle.write(contentsOf: data)
            }
        } else {
            try writeFile(at: url, content: content)
        }
    }

    public static func deleteFile(at url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public static func moveFile(from: URL, to: URL) throws {
        if fileManager.fileExists(atPath: to.path) {
            try fileManager.removeItem(at: to)
        }
        try fileManager.moveItem(at: from, to: to)
    }

    public static func copyFile(from: URL, to: URL) throws {
        if fileManager.fileExists(atPath: to.path) {
            try fileManager.removeItem(at: to)
        }
        try fileManager.copyItem(at: from, to: to)
    }

    public static func listDirectory(at url: URL) throws -> [URL] {
        return try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }

    public static func createDirectory(at url: URL) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
