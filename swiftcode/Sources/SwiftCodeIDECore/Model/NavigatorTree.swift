import Foundation
import SwiftCodeProject

public final class NavigatorNode: @unchecked Sendable {
    public enum Kind: Equatable, Sendable {
        case container
        case group
        case folder
        case file
    }

    public let name: String
    public let kind: Kind
    public let path: String?
    public let objectID: String?
    public internal(set) var children: [NavigatorNode]

    public init(name: String, kind: Kind, path: String?, objectID: String? = nil, children: [NavigatorNode] = []) {
        self.name = name
        self.kind = kind
        self.path = path
        self.objectID = objectID
        self.children = children
    }

    public var isExpandable: Bool { kind != .file }

    public var expansionKey: String { objectID ?? path ?? name }

    public var allFiles: [NavigatorNode] {
        kind == .file ? [self] : children.flatMap(\.allFiles)
    }

    public func find(path: String) -> NavigatorNode? {
        if self.path == path { return self }
        for c in children { if let f = c.find(path: path) { return f } }
        return nil
    }
}

public enum NavigatorTree {
    static let hidden: Set<String> = [".DS_Store", ".git", ".build", ".swiftpm", "xcuserdata", "DerivedData"]

    public static func project(_ proj: PBXProj, xcodeprojURL: URL) -> NavigatorNode {
        let dir = proj.projectDirectory(xcodeprojURL: xcodeprojURL)
        let parents = proj.parentMap()
        func node(_ id: String) -> NavigatorNode? {
            guard let obj = proj[id] else { return nil }
            let path = proj.resolvedPath(of: id, projectDirectory: dir, parents: parents)
            let display = obj.string("name") ?? obj.string("path").map { URL(fileURLWithPath: $0).lastPathComponent } ?? ""
            switch obj.isa {
            case "PBXGroup", "PBXVariantGroup", "XCVersionGroup":
                let kids = obj.references("children").compactMap(node)
                return NavigatorNode(name: display, kind: .group, path: path, objectID: id, children: kids)
            case "PBXFileSystemSynchronizedRootGroup":
                let kids = proj.synchronizedFolder(id, projectDirectory: dir, parents: parents).map(synchronized) ?? []
                return NavigatorNode(name: display, kind: .folder, path: path, objectID: id, children: kids)
            case "PBXFileReference":
                return NavigatorNode(name: display, kind: .file, path: path, objectID: id)
            default:
                return nil
            }
        }
        let main = proj.project?.string("mainGroup").flatMap { proj[$0] }
        let products = proj.project?.string("productRefGroup")
        let kids = main?.references("children").filter { $0 != products }.compactMap(node) ?? []
        let name = xcodeprojURL.deletingPathExtension().lastPathComponent
        return NavigatorNode(name: name, kind: .container, path: xcodeprojURL.path, objectID: proj.rootObject, children: kids)
    }

    public static func synchronized(_ folder: SynchronizedFolder) -> [NavigatorNode] {
        func rows(_ entries: [SynchronizedFolder.Entry]) -> [NavigatorNode] {
            var out: [NavigatorNode] = []
            var regions: [String: NavigatorNode] = [:]
            for e in entries {
                let full = folder.directory + "/" + e.path
                switch e.kind {
                case .group: out.append(NavigatorNode(name: e.name, kind: .folder, path: full, children: rows(e.children)))
                case .file: out.append(NavigatorNode(name: e.name, kind: .file, path: full))
                case .variantGroup:
                    for r in e.children {
                        let dir = folder.directory + "/" + (r.path as NSString).deletingLastPathComponent
                        let node = regions[dir] ?? {
                            let n = NavigatorNode(name: (dir as NSString).lastPathComponent, kind: .folder, path: dir)
                            regions[dir] = n
                            out.append(n)
                            return n
                        }()
                        node.children.append(NavigatorNode(name: e.name, kind: .file, path: folder.directory + "/" + r.path))
                    }
                }
            }
            for n in regions.values { n.children.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending } }
            return foldersFirst(out)
        }
        return rows(folder.entries)
    }

    public static func foldersFirst(_ rows: [NavigatorNode]) -> [NavigatorNode] {
        rows.sorted { a, b in
            let fa = a.kind == .folder, fb = b.kind == .folder
            if fa != fb { return fa }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    public static func directory(_ path: String) -> [NavigatorNode] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return names.filter { !hidden.contains($0) && !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { name in
                let full = (path as NSString).appendingPathComponent(name)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: full, isDirectory: &isDir)
                let isBundle = ["xcassets", "xcodeproj", "xcworkspace", "playground", "xcdatamodeld", "bundle"]
                    .contains((name as NSString).pathExtension)
                if isDir.boolValue && !isBundle {
                    return NavigatorNode(name: name, kind: .folder, path: full, children: directory(full))
                }
                return NavigatorNode(name: name, kind: .file, path: full)
            }
    }

    public static func initiallyExpanded(_ root: NavigatorNode) -> [String] {
        if isPackageRoot(root) {
            let folders = root.children.filter { $0.kind == .folder && ($0.name == "Sources" || $0.name == "Tests") }
            if !folders.isEmpty { return [root.expansionKey] + folders.map(\.expansionKey) }
        }
        return [root.expansionKey] + (root.children.first(where: \.isExpandable).map { [$0.expansionKey] } ?? [])
    }

    static func isPackageRoot(_ n: NavigatorNode) -> Bool {
        guard n.kind == .container, let p = n.path else { return false }
        return !p.hasSuffix(".xcodeproj") && !p.hasSuffix(".xcworkspace")
    }

    public static func package(at dir: URL) -> NavigatorNode {
        NavigatorNode(name: dir.lastPathComponent, kind: .container, path: dir.path, children: packageOrder(directory(dir.path)))
    }

    static func packageOrder(_ rows: [NavigatorNode]) -> [NavigatorNode] {
        func rank(_ n: NavigatorNode) -> Int {
            switch (n.name, n.kind) {
            case ("Package.swift", .file): 0
            case ("Sources", .folder): 1
            case ("Tests", .folder): 2
            default: 3
            }
        }
        return rows.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }
}
