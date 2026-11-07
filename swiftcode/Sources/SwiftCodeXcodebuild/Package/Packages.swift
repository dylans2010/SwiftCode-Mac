import Foundation
import SwiftCodeProject

enum PackageReport {
    struct Entry: Equatable {
        var name: String
        var location: String
        var state: String?
    }

    static func entries(_ c: Container, derivedDataRoot: String, checkouts: String? = nil) -> [Entry] {
        let resolved = c.workspacePath.appendingPathComponent("xcshareddata/swiftpm/Package.resolved")
        let checkouts = checkouts ?? derivedDataRoot + "/" + DerivedDataName.folder(name: c.name, path: c.url.path)
            + "/SourcePackages/checkouts"
        var pins: [Entry] = []
        if let data = FileManager.default.contents(atPath: resolved.path),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let list = obj["pins"] as? [[String: Any]] ?? (obj["object"] as? [String: Any])?["pins"] as? [[String: Any]] ?? []
            for pin in list {
                let location = pin["location"] as? String ?? pin["repositoryURL"] as? String ?? ""
                let state = pin["state"] as? [String: Any] ?? [:]
                let revision = String((state["revision"] as? String ?? "").prefix(7))
                let version = state["version"] as? String ?? (state["branch"] as? String).map { "\($0) (\(revision))" } ?? revision
                var repo = URL(fileURLWithPath: location).lastPathComponent
                if repo.hasSuffix(".git") { repo.removeLast(4) }
                let manifest = (try? String(contentsOfFile: checkouts + "/" + repo + "/Package.swift", encoding: .utf8))
                    ?? (try? String(contentsOfFile: checkouts + "/" + repo.lowercased() + "/Package.swift", encoding: .utf8))
                pins.append(Entry(name: manifest.flatMap(LocalPackages.packageName) ?? repo, location: location, state: version))
            }
        }
        func sameRepo(_ a: String, _ b: String) -> Bool {
            func n(_ s: String) -> String { var s = s.lowercased(); if s.hasSuffix(".git") { s.removeLast(4) }; return s }
            return n(a) == n(b)
        }
        var out: [Entry] = []
        for p in c.projects {
            let locals = LocalPackages.find(in: p)
            for ref in LocalPackages.references(in: p) {
                if let dir = ref.local, let pkg = locals.first(where: { $0.directory == dir }), !out.contains(where: { $0.location == dir }) {
                    out.append(Entry(name: pkg.name, location: dir, state: pkg.addedAsFolder ? nil : "local"))
                } else if let url = ref.remote, let pin = pins.first(where: { sameRepo($0.location, url) }), !out.contains(pin) {
                    out.append(pin)
                }
            }
        }
        for pin in pins where !out.contains(pin) { out.append(pin) }
        for p in c.projects {
            for pkg in LocalPackages.find(in: p) where !pkg.isPackageReference && !out.contains(where: { $0.location == pkg.directory }) {
                out.append(Entry(name: pkg.name, location: pkg.directory, state: nil))
            }
        }
        return out
    }

    static func print(_ c: Container, derivedDataRoot: String, checkouts: String? = nil, console: Console) {
        print(entries(c, derivedDataRoot: derivedDataRoot, checkouts: checkouts), console: console)
    }

    static func print(_ e: [Entry], console: Console) {
        guard !e.isEmpty else { return }
        console.out("Resolve Package Graph")
        console.out()
        console.out()
        console.out("Resolved source packages:")
        for x in e { console.out("  \(x.name): \(x.location)" + (x.state.map { " @ \($0)" } ?? "")) }
        console.out()
    }
}

enum ShellQuote {
    static func isPlain(_ c: Character) -> Bool {
        if !c.isASCII { return true }
        return c.isLetter || c.isNumber || ",+=-_./".contains(c)
    }

    static func quote(_ s: String) -> String {
        if !s.isEmpty && s.allSatisfy(isPlain) { return s }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
