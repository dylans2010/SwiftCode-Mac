import Foundation

package enum Trash {
    package static func move(_ url: URL) throws { _ = try moveReturningLocation(url) }

    @discardableResult
    package static func moveReturningLocation(_ url: URL) throws -> URL {
        #if canImport(Darwin)
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
        return (result as URL?) ?? url
        #else
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment
        let data = env["XDG_DATA_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent(".local/share")
        let trash = data.appendingPathComponent("Trash")
        let files = trash.appendingPathComponent("files"), info = trash.appendingPathComponent("info")
        try fm.createDirectory(at: files, withIntermediateDirectories: true)
        try fm.createDirectory(at: info, withIntermediateDirectories: true)
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var name = url.lastPathComponent, n = 1
        while fm.fileExists(atPath: files.appendingPathComponent(name).path)
                || fm.fileExists(atPath: info.appendingPathComponent(name + ".trashinfo").path) {
            n += 1
            name = "\(base) \(n)" + (ext.isEmpty ? "" : ".\(ext)")
        }
        let date = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                               formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate])
        let path = url.standardizedFileURL.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? url.path
        try "[Trash Info]\nPath=\(path)\nDeletionDate=\(date)\n".write(to: info.appendingPathComponent(name + ".trashinfo"), atomically: true, encoding: .utf8)
        try fm.moveItem(at: url, to: files.appendingPathComponent(name))
        return files.appendingPathComponent(name)
        #endif
    }

    package static func restore(_ trashed: URL, to original: URL) throws {
        try FileManager.default.moveItem(at: trashed, to: original)
        #if !canImport(Darwin)
        let info = trashed.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("info").appendingPathComponent(trashed.lastPathComponent + ".trashinfo")
        if FileManager.default.fileExists(atPath: info.path) { try? FileManager.default.removeItem(at: info) }
        #endif
    }
}
