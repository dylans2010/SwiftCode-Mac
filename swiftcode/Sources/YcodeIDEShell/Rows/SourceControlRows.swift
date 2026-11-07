import Foundation
import YcodeIDECore

public enum SourceControlRows {
    public static let modeTitles = ["Changes", "Repositories"]

    public static func repositoryName(_ s: SourceControlSnapshot) -> String {
        s.repository?.root.lastPathComponent ?? ""
    }

    public static func integrationSuffix(_ state: GitRepository.IntegrationState) -> String {
        switch state {
        case .none: ""
        case .merging(let b): " (Merging \u{201C}\(b)\u{201D})"
        case .rebasing(let b, let onto, let step, let total):
            " (Rebasing \u{201C}\(b)\u{201D} onto \(onto)" + (total > 0 ? ", \(step) of \(total))" : ")")
        case .cherryPicking(let c): " (Cherry-picking \(c.prefix(7)))"
        case .reverting(let c): " (Reverting \(c.prefix(7)))"
        }
    }

    public static func changeTitle(_ path: String, root: URL?) -> String {
        let rel = root.map { path.hasPrefix($0.path + "/") ? String(path.dropFirst($0.path.count + 1)) : path } ?? path
        let comps = rel.split(separator: "/")
        if let i = comps.firstIndex(where: { $0.hasSuffix(".xcodeproj") }), i + 1 < comps.count, comps[i + 1] == "project.xcworkspace" {
            return "\(comps[i].dropLast(".xcodeproj".count)) / project.xcworkspace"
        }
        let name = (path as NSString).lastPathComponent
        let bare = (name as NSString).deletingPathExtension
        return bare.isEmpty ? name : bare
    }

    public static func changes(_ s: SourceControlSnapshot, collapsed: Set<String>) -> [OutlineRow] {
        guard s.repository != nil else { return [] }
        var out = [header(s, collapsed: collapsed)]
        guard !collapsed.contains("repository") else { return out }
        let gid = "group:Uncommitted Changes"
        let open = !collapsed.contains(gid)
        out.append(OutlineRow(id: gid, level: 1, title: "Uncommitted Changes", symbol: "square.and.pencil", tint: .secondary,
                              isExpandable: !s.changes.isEmpty, isExpanded: open, trailing: String(s.changes.count)))
        guard open else { return out }
        for c in s.changes {
            out.append(OutlineRow(id: "change:" + c.path, level: 2, title: changeTitle(c.path, root: s.repository?.root),
                                  symbol: WorkspaceChrome.fileSymbol(c.path), tint: .accent, opens: true, badge: c.status.rawValue))
        }
        return out
    }

    static func header(_ s: SourceControlSnapshot, collapsed: Set<String>) -> OutlineRow {
        OutlineRow(id: "repository", level: 0, title: repositoryName(s), detail: (s.currentBranch ?? "HEAD") + integrationSuffix(s.integration),
                   symbol: RepositoriesViewStyle.repositorySymbol, tint: .secondary, isBold: true, isExpandable: true, isExpanded: !collapsed.contains("repository"),
                   detailIsSecondary: true)
    }

    public static func repositories(_ s: SourceControlSnapshot, collapsed: Set<String>) -> [OutlineRow] {
        guard s.repository != nil else { return [] }
        var out = [header(s, collapsed: collapsed)]
        guard !collapsed.contains("repository") else { return out }
        func group(_ title: String, _ children: (Int) -> [OutlineRow], empty: Bool) {
            let id = "group:" + title
            let open = !collapsed.contains(id)
            out.append(OutlineRow(id: id, level: 1, title: title, symbol: RepositoriesViewStyle.groupSymbols[title] ?? "folder.fill",
                                  tint: .secondary, isExpandable: true, isExpanded: open))
            if open { out += children(2) }
        }
        group("Branches", { foldered(s.branches.map(\.name), current: s.currentBranch, key: "branch:", symbol: "arrow.triangle.branch",
                                     level: $0, collapsed: collapsed) }, empty: s.branches.isEmpty)
        group("Recents", { level in s.recentBranches.map { OutlineRow(id: "recent:" + $0, level: level, title: $0, symbol: "clock.arrow.circlepath", tint: .secondary) } },
              empty: s.recentBranches.isEmpty)
        group("Tags", { foldered(s.tags.map(\.name), current: nil, key: "tag:", symbol: "tag", level: $0, collapsed: collapsed) }, empty: s.tags.isEmpty)
        group("Stashes", { level in
            s.stashes.map { line in
                let ref = line.components(separatedBy: ": ").first ?? line
                let rest = String(line.dropFirst(min(line.count, ref.count + 2)))
                return OutlineRow(id: "stash:" + ref, level: level, title: rest.isEmpty ? ref : rest, symbol: "tray", tint: .secondary)
            }
        }, empty: s.stashes.isEmpty)
        group("Remotes", { level in
            var rows: [OutlineRow] = []
            for r in s.remotes {
                let id = "remote:" + r.name
                let names = s.remoteBranches.filter { $0.name.hasPrefix(r.name + "/") }.map { String($0.name.dropFirst(r.name.count + 1)) }
                let open = !collapsed.contains(id)
                rows.append(OutlineRow(id: id, level: level, title: r.name, detail: r.url, symbol: "cloud", tint: .secondary,
                                       isExpandable: !names.isEmpty, isExpanded: open, detailIsSecondary: true))
                if open { rows += foldered(names, current: nil, key: "remoteBranch:\(r.name)/", symbol: "arrow.triangle.branch", level: level + 1, collapsed: collapsed) }
            }
            return rows
        }, empty: s.remotes.isEmpty)
        return out
    }

    static func foldered(_ names: [String], current: String?, key: String, symbol: String, level: Int, collapsed: Set<String>) -> [OutlineRow] {
        var leaves: [OutlineRow] = []
        var folders: [String: [String]] = [:]
        var order: [String] = []
        for n in names.sorted() {
            if let slash = n.firstIndex(of: "/") {
                let head = String(n[..<slash])
                if folders[head] == nil { order.append(head) }
                folders[head, default: []].append(String(n[n.index(after: slash)...]))
            } else {
                leaves.append(OutlineRow(id: key + n, level: level, title: n, symbol: symbol, tint: .secondary, detailIsSecondary: true))
            }
        }
        var out: [OutlineRow] = []
        for head in order {
            let id = "folder:" + key + head
            let open = !collapsed.contains(id)
            out.append(OutlineRow(id: id, level: level, title: head, symbol: "folder", tint: .accent, isExpandable: true, isExpanded: open))
            if open {
                let sub = current.flatMap { $0.hasPrefix(head + "/") ? String($0.dropFirst(head.count + 1)) : nil }
                out += foldered(folders[head] ?? [], current: sub, key: key + head + "/", symbol: symbol, level: level + 1, collapsed: collapsed)
            }
        }
        return out + leaves
    }
}

public struct ChangeCard: Identifiable, Equatable, Sendable {
    public var path: String
    public var title: String
    public var status: GitRepository.FileStatus
    public var isStaged: Bool
    public var lines: [UnifiedDiffLines.Line]
    public var id: String { path }
    public var symbol: String { WorkspaceChrome.fileSymbol(path) }
    public var stats: (added: Int, removed: Int) {
        (lines.filter { $0.kind == .added }.count, lines.filter { $0.kind == .removed }.count)
    }

    public static func == (a: Self, b: Self) -> Bool {
        a.path == b.path && a.title == b.title && a.status == b.status && a.isStaged == b.isStaged && a.lines == b.lines
    }
}

public struct CommitDetail: Equatable, Sendable {
    public var commit: GitRepository.Commit
    public var files: [CommitFile]
    public var branches: [String]
}

public struct CommitFile: Equatable, Sendable, Identifiable {
    public var path: String
    public var status: GitRepository.FileStatus
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
    public var symbol: String { WorkspaceChrome.fileSymbol(path) }
}

public struct CommitSheetFile: Identifiable, Equatable, Sendable {
    public var path: String
    public var relativePath: String
    public var status: GitRepository.FileStatus
    public var isOn = true
    public var id: String { path }
}

public struct CommitSheet: Equatable, Sendable {
    public var files: [CommitSheetFile]
    public var message = ""
    public var error: String?
    public var canCommit: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && files.contains(where: \.isOn)
    }
}

public struct SourceControlPrompt: Equatable, Sendable {
    public enum Purpose: Equatable, Sendable {
        case newBranch(from: String?)
        case newTag(at: String?)
        case renameBranch(String)
        case addRemote
        case stash
        case exportStash(String)
    }

    public struct Field: Equatable, Sendable {
        public var label: String
        public var placeholder: String
        public var text: String
    }

    public var purpose: Purpose
    public var title: String
    public var message: String
    public var fields: [Field]
    public var button: String
    public var canConfirm: Bool {
        if case .stash = purpose { return true }
        return fields.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

public struct SourceControlConfirmation: Equatable, Sendable {
    public struct Choice: Equatable, Sendable {
        public var title: String
        public var isDestructive: Bool
        public var action: SourceControlShellModel.Operation
    }

    public var title: String
    public var message: String
    public var choices: [Choice]
}
