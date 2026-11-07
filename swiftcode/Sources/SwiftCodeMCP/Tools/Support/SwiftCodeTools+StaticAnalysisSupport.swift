import Foundation
import SwiftCodeAssistant
import SwiftCodeIDECore

extension SwiftCodeMCPHost {
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

    nonisolated static func staticAnalysisReadLines(_ url: URL) -> [String]? {
        (try? String(contentsOf: url, encoding: .utf8))?.components(separatedBy: .newlines)
    }

    nonisolated static func staticAnalysisReadText(_ url: URL) -> String? {
        try? String(contentsOf: url, encoding: .utf8)
    }

    nonisolated static func staticAnalysisFileSize(_ url: URL) -> Int {
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]), let size = values.fileSize { return size }
        return 0
    }

    nonisolated static func staticAnalysisRelative(_ url: URL, root: URL) -> String {
        let rootPath = root.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") { return String(path.dropFirst(rootPath.count + 1)) }
        return path
    }

    nonisolated static func staticAnalysisDeclaredFuncName(_ line: String) -> String? {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("func ") || t.contains(" func ") else { return nil }
        guard let r = t.range(of: "func ") else { return nil }
        let rest = String(t[r.upperBound...])
        let name = rest.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" }).first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    nonisolated static func staticAnalysisInt(_ value: AnyJSON?, default defaultValue: Int) -> Int {
        if let i = value?.int { return i }
        if let s = value?.string, let i = Int(s.trimmingCharacters(in: .whitespaces)) { return i }
        return defaultValue
    }

    nonisolated static let staticAnalysisProtectedModules: Set<String> = [
        "Foundation", "Swift", "SwiftUI", "UIKit", "AppKit", "Combine", "CoreData", "SwiftData",
        "CoreGraphics", "CoreAnimation", "QuartzCore", "WebKit", "MapKit", "AVFoundation", "Photos",
        "UserNotifications", "StoreKit", "Testing", "XCTest", "Observation", "OSLog",
        "UniformTypeIdentifiers", "CryptoKit", "Security", "Network", "WidgetKit", "AppIntents",
        "TipKit", "CoreLocation", "CoreMotion", "HealthKit", "EventKit", "Contacts",
        "SafariServices", "AuthenticationServices", "LocalAuthentication", "Speech", "Vision",
        "NaturalLanguage", "PlaygroundSupport",
    ]

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
