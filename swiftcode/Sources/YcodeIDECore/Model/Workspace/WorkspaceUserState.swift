import Foundation

public struct WorkspaceUserState: Codable, Equatable, Sendable {
    public var recentFiles: [String] = []
    public var expandedRows: [String]?
    public var destinations: [String: String] = [:]
    public var debugAreaHeight: Double?

    public init() {}

    public static let recentFileLimit = 20

    public static func fileURL(container: URL, isPackage: Bool, user: String = NSUserName()) -> URL {
        let base = isPackage ? container.appendingPathComponent(".swiftpm/xcode") : container
        return base.appendingPathComponent("xcuserdata/\(user).xcuserdatad/swiftcode-ui-state.json")
    }

    public static func load(from url: URL) -> WorkspaceUserState {
        guard let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return s
    }

    public func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(self).write(to: url, options: .atomic)
    }

    public mutating func noteRecentFile(_ path: String) {
        recentFiles.removeAll { $0 == path }
        recentFiles.append(path)
        if recentFiles.count > Self.recentFileLimit { recentFiles.removeFirst(recentFiles.count - Self.recentFileLimit) }
    }

    public var existingRecentFiles: [String] { recentFiles.filter { FileManager.default.fileExists(atPath: $0) } }
}
