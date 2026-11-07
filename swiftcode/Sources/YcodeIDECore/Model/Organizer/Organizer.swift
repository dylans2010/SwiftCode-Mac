import Foundation
import YcodeXcodebuild

public struct ArchiveEntry: Equatable, Sendable {
    public var url: URL
    public var name: String
    public var scheme: String?
    public var created: Date?
    public var appName: String
    public var version: String?
    public var build: String?
    public var bundleIdentifier: String?
    public var architectures: [String]
    public var comment: String
    public var hasApplication: Bool

    public var versionText: String {
        switch (version, build) {
        case let (v?, b?): "\(v) (\(b))"
        case let (v?, nil): v
        case let (nil, b?): b
        default: ""
        }
    }

    public var status = "Archived"
}

public enum Organizer {
    public static var defaultArchivesDirectory: URL {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Developer/Xcode/Archives")
    }

    public static func entry(at url: URL) -> ArchiveEntry? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let app = plist["ApplicationProperties"] as? [String: Any]
        let appPath = app?["ApplicationPath"] as? String
        let name = plist["Name"] as? String ?? url.deletingPathExtension().lastPathComponent
        return ArchiveEntry(
            url: url, name: name, scheme: plist["SchemeName"] as? String, created: plist["CreationDate"] as? Date,
            appName: appPath.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? name,
            version: app?["CFBundleShortVersionString"] as? String, build: app?["CFBundleVersion"] as? String,
            bundleIdentifier: app?["CFBundleIdentifier"] as? String, architectures: app?["Architectures"] as? [String] ?? [],
            comment: plist["Comment"] as? String ?? "", hasApplication: appPath != nil)
    }

    public static func archives(in root: URL = defaultArchivesDirectory) -> [ArchiveEntry] {
        let fm = FileManager.default
        var urls: [URL] = []
        for item in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if item.pathExtension == "xcarchive" { urls.append(item); continue }
            for inner in (try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)) ?? [] where inner.pathExtension == "xcarchive" {
                urls.append(inner)
            }
        }
        return urls.compactMap(entry(at:)).sorted {
            let a = $0.created ?? .distantPast
            let b = $1.created ?? .distantPast
            if a != b { return a > b }
            return $0.url.path > $1.url.path
        }
    }

    public static func grouped(_ list: [ArchiveEntry]) -> [(app: String, archives: [ArchiveEntry])] {
        Dictionary(grouping: list, by: \.appName).map { ($0.key, $0.value) }
            .sorted { $0.app.localizedStandardCompare($1.app) == .orderedAscending }
    }

    public static func exportCopy(_ archive: URL, to exportPath: URL, home: String = NSHomeDirectory()) -> (status: Int32, output: String) {
        let options = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-export-\(UUID().uuidString).plist")
        defer { try? FileManager.default.removeItem(at: options) }
        let plist: [String: Any] = ["method": "mac-application"]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
              (try? data.write(to: options)) != nil else { return (70, "Could not write export options") }
        return run(["-exportArchive", "-archivePath", archive.path, "-exportPath", exportPath.path, "-exportOptionsPlist", options.path], home: home)
    }

    public static func archive(container: URL, scheme: String, archivePath: URL? = nil, home: String = NSHomeDirectory()) -> (status: Int32, output: String) {
        var args = [container.pathExtension == "xcworkspace" ? "-workspace" : "-project", container.path, "-scheme", scheme, "archive"]
        if let archivePath { args += ["-archivePath", archivePath.path] }
        return run(args, home: home, cwd: container.deletingLastPathComponent().path)
    }

    static func run(_ args: [String], home: String, cwd: String = FileManager.default.currentDirectoryPath) -> (status: Int32, output: String) {
        let capture = CapturingConsole()
        var ctx = XcodebuildContext.current(console: capture.console)
        ctx.home = home
        ctx.cwd = cwd
        let status = Xcodebuild.run(args, context: ctx)
        return (status, capture.stdout + capture.stderr)
    }
}
