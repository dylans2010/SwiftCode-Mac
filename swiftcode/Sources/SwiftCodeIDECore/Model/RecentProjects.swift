import Foundation

@MainActor
public final class RecentProjects {
    public static let didChange = Notification.Name("SwiftCodeRecentProjectsDidChange")
    public static var shared = RecentProjects(defaults: IDEProcess.isTestProcess
        ? UserDefaults(suiteName: NSTemporaryDirectory() + "swiftcode-recent-projects-\(ProcessInfo.processInfo.processIdentifier)") ?? .standard
        : .standard)

    public static let defaultsKey = "SwiftCode.recentProjects"
    public static let limit = 10

    let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var urls: [URL] {
        let stored = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        let present = stored.filter { FileManager.default.fileExists(atPath: $0) }
        if present.count != stored.count { defaults.set(present, forKey: Self.defaultsKey) }
        return present.map { URL(fileURLWithPath: $0) }
    }

    public func note(_ url: URL) {
        let path = Self.containerURL(url).path
        var list = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        list.removeAll { $0 == path }
        list.insert(path, at: 0)
        defaults.set(Array(list.prefix(Self.limit)), forKey: Self.defaultsKey)
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
        let rootURL = Self.containerURL(url)
        let name = rootURL.deletingPathExtension().lastPathComponent
        let ext = rootURL.pathExtension.lowercased()
        let kind: ProjectKind
        if ext == "xcodeproj" {
            kind = .xcodeProject
        } else if FileManager.default.fileExists(
            atPath: rootURL.appendingPathComponent("Package.swift").path) {
            kind = .swiftPackage
        } else {
            kind = .folder
        }
        Task { try? await ProjectRegistryStore.shared.note(rootURL: rootURL, name: name, kind: kind) }
    }

    public func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
        persist()
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    private func persist() {
        #if os(Linux)
        defaults.synchronize()
        #endif
    }

    static func containerURL(_ url: URL) -> URL {
        let u = url.standardizedFileURL
        return u.lastPathComponent == "Package.swift" ? u.deletingLastPathComponent() : u
    }

    public static func menuTitles(_ urls: [URL]) -> [String] {
        let names = urls.map(\.lastPathComponent)
        let counts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        return zip(urls, names).map { url, name in
            counts[name, default: 0] > 1 ? "\(name) \u{2014}  \(url.deletingLastPathComponent().lastPathComponent)" : name
        }
    }

    public static func displayName(_ url: URL) -> String {
        url.pathExtension.isEmpty ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    public static func folderText(_ url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        let parts = folder.pathComponents
        if parts.count >= 3, parts[1] == "Volumes" {
            return parts[2...].joined(separator: "/")
        }
        let values = try? folder.resourceValues(forKeys: [.volumeNameKey])
        guard let volume = values?.volumeName else { return folder.path }
        return ([volume] + parts.dropFirst()).joined(separator: "/")
    }
}
