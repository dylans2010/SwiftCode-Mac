import Foundation

extension GitRepository {
    public func stageNavigatorChanges(_ paths: [String]) {
        func real(_ p: String) -> String {
            let u = URL(fileURLWithPath: p).standardizedFileURL
            return u.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(u.lastPathComponent).path
        }
        let top = root.resolvingSymlinksInPath().path + "/"
        for p in Set(paths) {
            let full = real(p)
            guard full.hasPrefix(top) else { continue }
            _ = try? git(["add", "-A", "--", String(full.dropFirst(top.count))])
        }
    }
}
