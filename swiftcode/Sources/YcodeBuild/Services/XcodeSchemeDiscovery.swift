import Foundation
import YcodeSubprocess
import YcodeWorkspace

public protocol XcodebuildListRunner: Sendable {
    func listJSON(containerArgs: [String], workingDirectory: URL) async -> Data?
}

public struct DefaultXcodebuildListRunner: XcodebuildListRunner {
    public init() {}

    public func listJSON(containerArgs: [String], workingDirectory: URL) async -> Data? {
        #if os(macOS)
        let xcodebuild = URL(fileURLWithPath: "/usr/bin/xcodebuild")
        guard FileManager.default.fileExists(atPath: xcodebuild.path) else { return nil }
        return await Task.detached {
            guard let out = try? Subprocess.run(
                "/usr/bin/xcodebuild",
                containerArgs + ["-list", "-json"],
                currentDirectory: workingDirectory
            ) else { return nil }
            guard out.status == 0 else { return nil }
            return out.stdout
        }.value
        #else
        return nil
        #endif
    }
}

public struct XcodeSchemeDiscovery: Sendable {
    public enum Source: String, Sendable {
        case explicit
        case listed
        case fileDiscovered
        case containerName
    }

    public struct ResolvedScheme: Sendable, Equatable {
        public var scheme: String
        public var source: Source
        public var reason: String?

        public init(scheme: String, source: Source, reason: String? = nil) {
            self.scheme = scheme
            self.source = source
            self.reason = reason
        }
    }

    public var listRunner: any XcodebuildListRunner

    public init(listRunner: any XcodebuildListRunner = DefaultXcodebuildListRunner()) {
        self.listRunner = listRunner
    }

    public func containerArgs(for container: BuildRequest.Container) -> [String]? {
        switch container {
        case .project(let path): return ["-project", path]
        case .workspace(let path): return ["-workspace", path]
        case .package: return nil
        }
    }

    public func containerName(for container: BuildRequest.Container) -> String {
        URL(fileURLWithPath: container.path).deletingPathExtension().lastPathComponent
    }

    public func listSchemes(container: BuildRequest.Container) -> [String] {
        let containerURL = URL(fileURLWithPath: container.path)
        var names: [String] = []
        switch container {
        case .project:
            names += Scheme.discover(in: containerURL).map { $0.name }
        case .workspace:
            names += Scheme.discover(in: containerURL).map { $0.name }
            let parent = containerURL.deletingLastPathComponent()
            if let entries = try? FileManager.default.contentsOfDirectory(
                at: parent, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for entry in entries where entry.pathExtension == "xcodeproj" {
                    names += Scheme.discover(in: entry).map { $0.name }
                }
            }
        case .package:
            break
        }
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }.sorted()
    }

    public static func parseListJSON(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        if let project = json["project"] as? [String: Any],
           let schemes = project["schemes"] as? [String] {
            return schemes
        }
        if let workspace = json["workspace"] as? [String: Any],
           let schemes = workspace["schemes"] as? [String] {
            return schemes
        }
        return []
    }

    public func listedSchemes(container: BuildRequest.Container) async -> [String] {
        guard let args = containerArgs(for: container) else { return [] }
        let workingDirectory = URL(fileURLWithPath: container.path).deletingLastPathComponent()
        guard let data = await listRunner.listJSON(containerArgs: args, workingDirectory: workingDirectory) else {
            return []
        }
        return Self.parseListJSON(data)
    }

    public func resolveScheme(explicit: String?, container: BuildRequest.Container) async -> ResolvedScheme {
        let trimmedExplicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines)
        if case .package = container {
            return ResolvedScheme(
                scheme: trimmedExplicit ?? "",
                source: .explicit,
                reason: "SwiftPM package: packages have no .xcscheme files, so the target name is used as the scheme."
            )
        }
        let listed = await listedSchemes(container: container)
        let filed = listSchemes(container: container)
        if let explicit = trimmedExplicit, !explicit.isEmpty {
            if listed.contains(explicit) || filed.contains(explicit) {
                return ResolvedScheme(scheme: explicit, source: .explicit)
            }
        }
        if let first = listed.first {
            return ResolvedScheme(
                scheme: first,
                source: .listed,
                reason: trimmedExplicit.map {
                    "“\($0)” is not a scheme in this container; using the first scheme from xcodebuild -list."
                }
            )
        }
        if let first = filed.first {
            return ResolvedScheme(
                scheme: first,
                source: .fileDiscovered,
                reason: "xcodebuild -list reported no schemes (or the tool is unavailable); using the first .xcscheme file on disk."
            )
        }
        let fallback = (trimmedExplicit?.isEmpty == false) ? trimmedExplicit! : containerName(for: container)
        return ResolvedScheme(
            scheme: fallback,
            source: .containerName,
            reason: "No schemes could be discovered (xcodebuild -list unavailable or empty and no .xcscheme files); using the \(trimmedExplicit?.isEmpty == false ? "requested target" : "container name") as the scheme, as before."
        )
    }
}
