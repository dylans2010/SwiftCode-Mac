import Foundation
import SwiftCodeSubprocess
import SwiftCodeWorkspace

// MARK: - Build scheme discovery (Wave 16, Slice D)
//
// Ported from Legacy (Dylan's own code; direct port authorised under
// MIT, spec-first where it costs nothing):
//   * `SwiftCode/Backend/Assist/Tools/AssistXcodeProjectResolver.swift`
//     — `locate`, `resolveScheme`, `firstListedScheme`
//     (`xcodebuild -list -json`, explicit scheme wins, else the
//     first listed scheme, else the project bundle's base name).
//
// SwiftCode already has the pieces Legacy's resolver re-implemented:
// `Scheme.discover(in:user:)` (SwiftCodeWorkspace) reads shared and
// user `.xcscheme` files from a container, and the `xcodebuild`
// reimplementation reports the same `-list` JSON shape. This seam
// composes them in Legacy's precedence order, reusing SwiftCode's
// machinery instead of duplicating it:
//
//   1. An explicit scheme — but only when it names a scheme this
//      container actually has. (Deliberate deviation from Legacy:
//      Legacy's explicit parameter was a user-supplied *scheme*;
//      the callers here pass a *target* name, which is often not
//      a scheme. Using it blindly reproduces the old bug — the
//      target used as the scheme. An unknown explicit name falls
//      through to discovery and is used only as the last resort.)
//   2. The first scheme from `xcodebuild -list -json`.
//   3. The first scheme from the `.xcscheme` files on disk
//      (shared, then the current user's — `Scheme.discover`).
//   4. The explicit name, or the container bundle's base name
//      (Legacy's final fallback), with the exact reason recorded.
//
// The result always carries its source and, when the scheme did
// not come from discovery, the reason — so a caller (or a log)
// can tell a real scheme from a fallback. Discovery never throws
// and never fails a build: when `xcodebuild` is absent (Linux)
// or `-list` fails, the file leg still runs, and only the final
// fallback remains.
//
// Workspace containers: scheme files are read from the workspace
// bundle itself plus every sibling `.xcodeproj` in the same
// directory (the usual layout for workspace members). Members
// referenced from elsewhere are covered by the `xcodebuild -list`
// leg when it can run; the file leg does not parse
// `.xcworkspacedata`.

/// Runs `xcodebuild -list -json` for a container and returns its
/// stdout, or nil when the tool cannot run or fails. Injectable so
/// tests can stub the subprocess without a real `xcodebuild`.
public protocol XcodebuildListRunner: Sendable {
    func listJSON(containerArgs: [String], workingDirectory: URL) async -> Data?
}

/// The live runner: `/usr/bin/xcodebuild` on macOS only. On
/// Linux (or anywhere without the tool) it returns nil, and the
/// file leg is the only discovery that runs.
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

/// Resolves the scheme to build for a container.
public struct XcodeSchemeDiscovery: Sendable {
    /// Where the resolved scheme came from.
    public enum Source: String, Sendable {
        /// The explicit name, which names a scheme in this container.
        case explicit
        /// The first scheme from `xcodebuild -list -json`.
        case listed
        /// The first `.xcscheme` file on disk.
        case fileDiscovered
        /// The explicit name or container base name, used because
        /// no scheme could be discovered at all.
        case containerName
    }

    /// A resolved scheme, with its provenance. `reason` is set
    /// whenever the scheme is a fallback rather than a discovered
    /// scheme, so the caller can record exactly why.
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

    /// The `xcodebuild -project/-workspace` argument pair for a
    /// container, or nil for a package (packages have no schemes;
    /// the target name is the scheme there).
    public func containerArgs(for container: BuildRequest.Container) -> [String]? {
        switch container {
        case .project(let path): return ["-project", path]
        case .workspace(let path): return ["-workspace", path]
        case .package: return nil
        }
    }

    /// The container bundle's base name (Legacy's final fallback:
    /// the project name without extension).
    public func containerName(for container: BuildRequest.Container) -> String {
        URL(fileURLWithPath: container.path).deletingPathExtension().lastPathComponent
    }

    /// Scheme names from the `.xcscheme` files on disk, sorted,
    /// deduplicated. Projects read their own bundle; workspaces
    /// read their own bundle plus every sibling `.xcodeproj`;
    /// packages have none.
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

    /// The schemes in `xcodebuild -list -json` output
    /// (`{"project": {"schemes": [...]}}` or `{"workspace":
    /// {"schemes": [...]}}`). Anything unparseable yields no
    /// schemes (Legacy's rule: a failed parse is a missing list,
    /// not an error).
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

    /// The schemes `xcodebuild -list -json` reports for a
    /// container, or [] when the tool cannot run or the output
    /// does not parse.
    public func listedSchemes(container: BuildRequest.Container) async -> [String] {
        guard let args = containerArgs(for: container) else { return [] }
        let workingDirectory = URL(fileURLWithPath: container.path).deletingLastPathComponent()
        guard let data = await listRunner.listJSON(containerArgs: args, workingDirectory: workingDirectory) else {
            return []
        }
        return Self.parseListJSON(data)
    }

    /// Resolves the scheme to build, in Legacy's precedence
    /// order (explicit-when-known → first listed → first file →
    /// explicit-or-container name), with the reason recorded
    /// whenever the answer is a fallback.
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
