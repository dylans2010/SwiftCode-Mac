import Foundation
import YcodeLanguage

public enum LaunchAction: Equatable {
    case open([String])
    case welcome
    case none

    public static func decide(arguments: [String], openDocumentCount: Int) -> LaunchAction {
        let paths = LaunchArguments.documentPaths(arguments)
        if !paths.isEmpty { return .open(paths) }
        return openDocumentCount == 0 ? .welcome : .none
    }
}
public struct WelcomeLaunchGate: Equatable, Sendable {
    public private(set) var pending = 0
    public private(set) var launchChecked = false
    public private(set) var decided = false

    public init() {}

    public mutating func openRequested() { pending += 1 }

    public mutating func openFinished(openDocuments: Int) -> Bool {
        pending = max(0, pending - 1)
        return decide(openDocuments: openDocuments)
    }

    public mutating func launchCheck(openDocuments: Int) -> Bool {
        launchChecked = true
        return decide(openDocuments: openDocuments)
    }

    private mutating func decide(openDocuments: Int) -> Bool {
        guard launchChecked, !decided, pending == 0 else { return false }
        decided = true
        return openDocuments == 0
    }
}
public enum LaunchArguments {
    public static func documentPaths(_ args: [String]) -> [String] {
        var out: [String] = []
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--" { out += args[(i + 1)...]; break }
            if a.hasPrefix("-") && a.count > 1 {
                if i + 1 < args.count, !args[i + 1].hasPrefix("-") { i += 1 }
            } else {
                out.append(a)
            }
            i += 1
        }
        return out
    }
}

public enum OpenRequestKey {
    public static func path(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
}

extension NavigatorNode {
    public func containsForOpening(_ file: URL) -> Bool {
        let target = OpenRequestKey.path(file)
        func resolved(_ p: String) -> String { OpenRequestKey.path(URL(fileURLWithPath: p)) }
        func walk(_ n: NavigatorNode) -> Bool {
            if let p = n.path {
                switch n.kind {
                case .file: if resolved(p) == target { return true }
                case .folder: if target.hasPrefix(resolved(p) + "/") { return true }
                case .container: if NavigatorTree.isPackageRoot(n), target.hasPrefix(resolved(p) + "/") { return true }
                case .group: break
                }
            }
            return n.children.contains(where: walk)
        }
        return walk(self)
    }

    public func projectPath(forOpening file: URL) -> String? {
        let target = OpenRequestKey.path(file)
        func resolved(_ p: String) -> String { OpenRequestKey.path(URL(fileURLWithPath: p)) }
        var inFolder: String?
        func walk(_ n: NavigatorNode) -> String? {
            if let p = n.path {
                switch n.kind {
                case .file: if resolved(p) == target { return p }
                case .folder, .container:
                    let r = resolved(p)
                    if inFolder == nil, n.kind == .folder || NavigatorTree.isPackageRoot(n), target.hasPrefix(r + "/") {
                        inFolder = (p as NSString).appendingPathComponent(String(target.dropFirst(r.count + 1)))
                    }
                case .group: break
                }
            }
            for c in n.children { if let hit = walk(c) { return hit } }
            return nil
        }
        return walk(self) ?? inFolder
    }
}
