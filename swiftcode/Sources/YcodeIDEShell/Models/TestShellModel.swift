import Foundation
import Observation
import YcodeBuild
import YcodeIDECore

@MainActor
@Observable
public final class TestShellModel {
    @ObservationIgnored let session: WorkspaceSession

    public private(set) var tests: [DiscoveredTest] = []
    public private(set) var results: [DiscoveredTest: TestOutcome.Status] = [:]
    public private(set) var hasDiscovered = false
    public var collapsed: Set<String> = []
    public private(set) var selection: String?
    public private(set) var running: [DiscoveredTest]?
    public private(set) var reports: [BuildReport] = []
    public var reportCollapsed: Set<String> = []
    public private(set) var reportSelection: String?
    public private(set) var shownReport: (index: Int, page: String)?

    public init(session: WorkspaceSession) {
        self.session = session
        session.observe { [weak self] change in
            guard let self else { return }
            switch change {
            case .tests:
                self.tests = session.tests
                self.results = session.testResults
                self.hasDiscovered = true
            case .reports:
                self.reports = session.reports
            default: break
            }
        }
        session.discoverTests()
    }

    public func discover() {
        session.discoverTests()
    }

    public func discovered() async { await session.testsDiscovered() }

    public static func countText(_ n: Int) -> String { "\(n) Test\(n == 1 ? "" : "s")" }

    public static func aggregate(_ all: [TestOutcome.Status?]) -> TestOutcome.Status? {
        let known = all.compactMap { $0 }
        if known.contains(.failed) { return .failed }
        if known.contains(.passed) { return .passed }
        return known.isEmpty ? nil : .skipped
    }

    public static func diamond(_ s: TestOutcome.Status?) -> (symbol: String, tint: OutlineRow.Tint) {
        switch s {
        case .passed?: ("checkmark.diamond.fill", .success)
        case .failed?: ("xmark.diamond.fill", .error)
        case .skipped?: ("arrow.right.circle", .secondary)
        case nil: ("diamond", .secondary)
        }
    }

    public func target(of t: DiscoveredTest) -> String {
        if session.model.kind != .package, let name = session.model.targetName(compiling: t.file) { return name }
        let dir = URL(fileURLWithPath: t.file).deletingLastPathComponent()
        let parts = dir.pathComponents
        if let i = parts.lastIndex(of: "Tests"), i + 1 < parts.count { return parts[i + 1] }
        return dir.lastPathComponent
    }

    static func testID(_ t: DiscoveredTest) -> String { "test:\(t.file)#\(t.identifier)" }

    public var rows: [OutlineRow] {
        guard !tests.isEmpty else { return [] }
        var out: [OutlineRow] = []
        func status(_ list: [DiscoveredTest]) -> TestOutcome.Status? { Self.aggregate(list.map { results[$0] }) }
        func parent(_ id: String, _ level: Int, _ title: String, _ symbol: String, _ list: [DiscoveredTest], bold: Bool = false) -> Bool {
            let open = !collapsed.contains(id)
            let d = Self.diamond(status(list))
            out.append(OutlineRow(id: id, level: level, title: title, detail: Self.countText(list.count), symbol: symbol, tint: .secondary,
                                  isBold: bold, isExpandable: true, isExpanded: open, detailIsSecondary: true, trailingSymbol: d.symbol,
                                  trailingTint: d.tint))
            return open
        }
        let isPackage = session.model.kind == .package
        guard parent("tests:root", 0, session.model.displayName, isPackage ? "shippingbox" : "folder.badge.gearshape", tests, bold: true) else { return out }
        var targets: [(String, [DiscoveredTest])] = []
        for t in tests {
            let name = target(of: t)
            if let i = targets.firstIndex(where: { $0.0 == name }) { targets[i].1.append(t) } else { targets.append((name, [t])) }
        }
        for (target, list) in targets {
            guard parent("target:" + target, 1, target, "scope", list) else { continue }
            var suites: [(String, [DiscoveredTest])] = []
            for t in list {
                let key = t.suite ?? ""
                if let i = suites.firstIndex(where: { $0.0 == key }) { suites[i].1.append(t) } else { suites.append((key, [t])) }
            }
            for (suite, members) in suites {
                var level = 2
                if !suite.isEmpty {
                    guard parent("suite:\(target)/\(suite)", 2, suite, "c.square", members) else { continue }
                    level = 3
                }
                for t in members {
                    let d = Self.diamond(results[t])
                    out.append(OutlineRow(id: Self.testID(t), level: level, title: "\(t.name)()", symbol: "t.square", tint: .secondary,
                                          opens: true, trailingSymbol: d.symbol, trailingTint: d.tint))
                }
            }
        }
        return out
    }

    public func tests(forRow id: String) -> [DiscoveredTest] {
        if id == "tests:root" { return tests }
        if id.hasPrefix("target:") { let n = String(id.dropFirst(7)); return tests.filter { target(of: $0) == n } }
        if id.hasPrefix("suite:") {
            let rest = String(id.dropFirst(6))
            guard let slash = rest.firstIndex(of: "/") else { return [] }
            let tgt = String(rest[..<slash]), suite = String(rest[rest.index(after: slash)...])
            return tests.filter { target(of: $0) == tgt && $0.suite == suite }
        }
        return tests.filter { Self.testID($0) == id }
    }

    public func location(ofRow id: String) -> (file: String, line: Int)? {
        let list = tests(forRow: id)
        if id.hasPrefix("test:"), let t = list.first { return (t.file, t.line) }
        if id.hasPrefix("suite:"), let t = list.first { return (t.file, t.suiteLine ?? t.line) }
        return nil
    }

    public func select(_ id: String) { selection = id }

    public func setExpanded(_ id: String, _ on: Bool) {
        if on { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    public func isRunning(_ id: String) -> Bool {
        guard let r = running else { return false }
        if r.isEmpty { return true }
        let mine = Set(tests(forRow: id))
        return !mine.isDisjoint(with: r)
    }

    public func diamonds(in file: String) -> [Int: TestOutcome.Status?] {
        var out: [Int: TestOutcome.Status?] = [:]
        let mine = tests.filter { $0.file == file }
        for t in mine { out[t.line] = .some(results[t]) }
        var suites: [Int: [DiscoveredTest]] = [:]
        for t in mine { if let l = t.suiteLine { suites[l, default: []].append(t) } }
        for (line, members) in suites where out[line] == nil { out[line] = .some(Self.aggregate(members.map { results[$0] })) }
        return out
    }

    func noteRunning(_ only: [DiscoveredTest]) { running = only }
    func noteFinished() {
        running = nil
        tests = session.tests
        results = session.testResults
        reports = session.reports
    }

    public var reportRows: [OutlineRow] {
        var out: [OutlineRow] = []
        for g in ReportNavigatorModel.groups(reports) {
            let gid = "group:" + g.title
            let open = !reportCollapsed.contains(gid)
            out.append(OutlineRow(id: gid, level: 0, title: g.title, symbol: g.isPackage ? "shippingbox" : "app.dashed", tint: .accent,
                                  isBold: true, isExpandable: true, isExpanded: open))
            guard open else { continue }
            for r in g.rows {
                let rid = "report:\(r.index)"
                let ropen = !reportCollapsed.contains(rid)
                out.append(OutlineRow(id: rid, level: 1, title: r.title, detail: r.detail, symbol: Self.reportSymbol(r.symbol),
                                      tint: r.failed ? .error : .secondary, isExpandable: !r.children.isEmpty, isExpanded: ropen,
                                      opens: true, trailing: r.badge, detailIsSecondary: true))
                guard ropen else { continue }
                for c in r.children where Self.shownPages.contains(c.page ?? "") {
                    out.append(OutlineRow(id: "\(rid)/\(c.page ?? "")", level: 2, title: c.title, detail: c.detail,
                                          symbol: Self.reportSymbol(c.symbol), tint: c.failed ? .error : .secondary, opens: true,
                                          trailing: c.badge, detailIsSecondary: true))
                }
            }
        }
        return out
    }

    public static let shownPages: Set<String> = ["Tests", "Log"]

    static func reportSymbol(_ s: String) -> String {
        switch s {
        case "doc.plaintext": "doc.text"
        default: s
        }
    }

    public func selectReport(_ id: String) {
        reportSelection = id
        guard id.hasPrefix("report:") else { return }
        let rest = id.dropFirst(7)
        let parts = rest.split(separator: "/", maxSplits: 1)
        guard let i = Int(parts.first ?? ""), reports.indices.contains(i) else { return }
        let page = parts.count > 1 ? String(parts[1]) : (reports[i].kind == .test ? "Tests" : "Log")
        shownReport = (i, page)
    }

    public func setReportExpanded(_ id: String, _ on: Bool) {
        if on { reportCollapsed.remove(id) } else { reportCollapsed.insert(id) }
    }

    public func hideReport() { shownReport = nil }

    public var report: BuildReport? { shownReport.flatMap { reports.indices.contains($0.index) ? reports[$0.index] : nil } }

    public static func reportTests(_ r: BuildReport) -> [TestOutcome] {
        r.context.tests.sorted { a, b in
            let rank: (TestOutcome.Status) -> Int = { $0 == .failed ? 0 : ($0 == .skipped ? 2 : 1) }
            return rank(a.status) != rank(b.status) ? rank(a.status) < rank(b.status) : ((a.suite ?? ""), a.name) < ((b.suite ?? ""), b.name)
        }
    }

    public static func summary(_ r: BuildReport) -> String {
        let t = r.context.tests
        let p = t.filter { $0.status == .passed }.count, f = t.filter { $0.status == .failed }.count, s = t.filter { $0.status == .skipped }.count
        return "\(p) passed, \(f) failed" + (s > 0 ? ", \(s) skipped" : "")
    }
}
