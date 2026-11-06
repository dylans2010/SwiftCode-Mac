import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

/// Shared helpers for the ported Legacy static-analysis tool family
/// (Wave 6, slice B).
///
/// Behaviour source: Legacy's `AssistToolSharedHelpers`
/// (`AssistWorkspacePaths`, `AssistWorkspaceScan`) and the per-tool
/// private helpers in the 22 tools ported here (Dylan's own code,
/// ported under MIT), as specified in
/// `specs/ide/assist-testing-static-analysis.md`.
///
/// Two enumeration shapes exist in Legacy and both are preserved:
///
/// * The per-tool enumerator (`dead_code_scan`,
///   `duplicate_code_scan`, `todo_scan`, `import_cleanup`,
///   `concurrency_audit`): no hidden-file skip, skips the
///   `.git` / `DerivedData` / `.build` / `Pods` / `node_modules`
///   directories via `skipDescendants`, Swift files only, files over
///   300 KB dropped, at most 5000 files, sorted by path.
/// * `AssistWorkspaceScan.swiftFiles` (`force_unwrap_scan`,
///   `comment_density_report`, `function_size_report`,
///   `string_literal_audit`, `deprecation_usage_scan`,
///   `entry_points_discover`): skips hidden files and any file whose
///   first path component (relative to the root) is a skipped
///   directory (`.git`, `.build`, `build`, `DerivedData`, `.swiftpm`,
///   `Pods`, `Carthage`, `node_modules`, `.venv`), Swift files only,
///   at most 8000 files, enumerator order (not sorted).
///
/// The strict scan-path resolver mirrors Legacy's per-tool
/// `resolvePath`: an absent or blank path is the workspace root, any
/// `..` fails, a leading-`/` path must be under the root, and a
/// relative path is appended to the root (never the session working
/// directory). Single-file tools instead use the session-aware
/// `resolveFileReadingPath` (Wave 1), except `code_comment_extract`
/// and `swift_ast_inspector`, which use the strict
/// `resolveFileWritingPath` — the closest SwiftCode shape to Legacy's
/// `AssistWorkspacePaths.resolve` (rejects empty, NUL, a leading `~`
/// and any `..`).
extension SwiftCodeMCPHost {
    /// Legacy's strict per-tool scan resolver: `nil` when the path
    /// escapes the workspace (any `..`, or an absolute path outside
    /// the root), the workspace root when the path is absent or blank.
    @MainActor static func staticAnalysisResolveScanPath(_ raw: String?, in s: WorkspaceSession) -> URL? {
        let root = Self.folder(of: s.model).standardizedFileURL
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return root }
        guard !raw.contains("..") else { return nil }
        let candidate: URL
        if raw.hasPrefix("/") {
            candidate = URL(fileURLWithPath: raw).standardizedFileURL
        } else {
            candidate = root.appendingPathComponent(raw).standardizedFileURL
        }
        guard candidate.path == root.path || candidate.path.hasPrefix(root.path + "/") else { return nil }
        return candidate
    }

    /// The per-tool enumerator shape (see the header): Swift files
    /// only, at most 5000, sorted by path.
    nonisolated static func staticAnalysisEnumerateSwiftFiles(at root: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir) else { return [] }
        if !isDir.boolValue {
            return root.pathExtension.lowercased() == "swift" && staticAnalysisFileSize(root) <= 300_000 ? [root] : []
        }
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: []) else { return results }
        while let url = enumerator.nextObject() as? URL {
            let name = url.lastPathComponent
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                if name == ".git" || name == "DerivedData" || name == ".build" || name == "Pods" || name == "node_modules" {
                    enumerator.skipDescendants()
                }
                continue
            }
            if url.pathExtension.lowercased() != "swift" { continue }
            if staticAnalysisFileSize(url) > 300_000 { continue }
            results.append(url)
            if results.count >= 5000 { break }
        }
        return results.sorted { $0.path < $1.path }
    }

    /// Legacy's `AssistWorkspaceScan.swiftFiles` shape (see the
    /// header): hidden files and skipped top-level directories are
    /// omitted, enumerator order, at most 8000 files.
    nonisolated static func staticAnalysisSwiftFiles(under root: URL, maxFiles: Int = 8000) -> [URL] {
        let skippedDirs: Set<String> = [".git", ".build", "build", "DerivedData", ".swiftpm", "Pods", "Carthage", "node_modules", ".venv"]
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return results }
        let rootPath = root.standardized.path
        while let url = enumerator.nextObject() as? URL, results.count < maxFiles {
            let rel: String
            if url.standardized.path.hasPrefix(rootPath + "/") {
                rel = String(url.standardized.path.dropFirst(rootPath.count + 1))
            } else {
                rel = url.standardized.path
            }
            if skippedDirs.contains(rel.split(separator: "/").first.map(String.init) ?? "") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            if url.pathExtension.lowercased() != "swift" { continue }
            results.append(url)
        }
        return results
    }

    /// Legacy's plain directory enumeration (`code_metrics_analyzer`,
    /// `swift_migration_advisor`): no skipped directories, no size
    /// cap, enumerator order. A single file is returned as-is when it
    /// is a Swift file, otherwise `[]`.
    nonisolated static func staticAnalysisFilesForAnalysis(at target: URL) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else { return [] }
        if isDir.boolValue {
            var files: [URL] = []
            if let enumerator = FileManager.default.enumerator(at: target, includingPropertiesForKeys: nil) {
                while let fileURL = enumerator.nextObject() as? URL {
                    if fileURL.pathExtension == "swift" { files.append(fileURL) }
                }
            }
            return files
        }
        return target.pathExtension == "swift" ? [target] : []
    }

    /// A file's lines as UTF-8, or `nil` when it cannot be read.
    nonisolated static func staticAnalysisReadLines(_ url: URL) -> [String]? {
        (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
    }

    /// A file's UTF-8 text, or `nil` when it cannot be read.
    nonisolated static func staticAnalysisReadText(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    /// A file's size in bytes (0 when it cannot be read).
    nonisolated static func staticAnalysisFileSize(_ url: URL) -> Int {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize { return size }
        return 0
    }

    /// Workspace-relative display path (`"."` for the root itself),
    /// mirroring Legacy's `AssistWorkspacePaths.relative`.
    nonisolated static func staticAnalysisRelative(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
        return path
    }

    /// Function name declared on a `func ` line (strips generics and
    /// parameters), mirroring Legacy's `AssistWorkspaceScan`.
    nonisolated static func staticAnalysisDeclaredFuncName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("func ") || t.contains(" func ") else { return nil }
        guard let r = t.range(of: "func ") else { return nil }
        let rest = String(t[r.upperBound...])
        let name = rest.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    /// An integer argument, also from a whole double or a numeric
    /// string (Legacy's `duplicate_code_scan` accepts all three for
    /// `minLines`); `defaultValue` otherwise.
    nonisolated static func staticAnalysisInt(_ value: AnyJSON?, default defaultValue: Int) -> Int {
        if let i = value?.int { return i }
        if let s = value?.string, let i = Int(s.trimmingCharacters(in: .whitespaces)) { return i }
        return defaultValue
    }

    /// Modules `import_cleanup` never removes: their symbols do not
    /// mention the module name, so a whole-word usage check would
    /// wrongly delete them. Legacy's list, verbatim.
    nonisolated static let staticAnalysisProtectedModules: Set<String> = [
        "Foundation", "Swift", "SwiftUI", "UIKit", "AppKit", "Combine", "CoreData", "SwiftData",
        "CoreGraphics", "CoreAnimation", "QuartzCore", "WebKit", "MapKit", "AVFoundation", "Photos",
        "UserNotifications", "StoreKit", "Testing", "XCTest", "Observation", "OSLog",
        "UniformTypeIdentifiers", "CryptoKit", "Security", "Network", "WidgetKit", "AppIntents",
        "TipKit", "CoreLocation", "CoreMotion", "HealthKit", "EventKit", "Contacts",
        "SafariServices", "AuthenticationServices", "LocalAuthentication", "Speech", "Vision",
        "NaturalLanguage", "PlaygroundSupport",
    ]

    /// Known symbols per framework for `unused_imports_detector`:
    /// an import of one of these modules is "used" when any of its
    /// symbols (or an explicit `Module.` reference) appears in the
    /// file body. Legacy's map, verbatim. Modules absent from the map
    /// are never flagged.
    nonisolated static let staticAnalysisFrameworkSymbols: [String: [String]] = [
        "Combine": ["AnyCancellable", "PassthroughSubject", "CurrentValueSubject", "Publisher", "sink", "store", "eraseToAnyPublisher"],
        "SwiftUI": ["View", "body", "some View", "Text", "VStack", "HStack", "State", "Binding", "Environment", "Color"],
        "AppKit": ["NSView", "NSViewController", "NSWindow", "NSApplication", "NSColor", "NSImage", "NSPasteboard", "NSWorkspace"],
        "UIKit": ["UIView", "UIViewController", "UIWindow", "UIApplication", "UIColor", "UIImage", "UIFont"],
        "os": ["Logger", "os_log", "OSLog"],
        "WebKit": ["WKWebView", "WKNavigationDelegate"],
        "AVFoundation": ["AVPlayer", "AVAudioSession", "AVCaptureSession"],
        "CoreData": ["NSManagedObject", "NSManagedObjectContext", "NSPersistentContainer"],
    ]
}
