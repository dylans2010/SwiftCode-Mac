import Foundation
import SwiftCodeBuild
import SwiftCodeXcodebuild

public enum ReportLocation: String, Sendable { case local = "Local", cloud = "Cloud" }

public enum ReportKind: String, Sendable {
    case build = "Build", clean = "Clean", test = "Test", analyze = "Analyze"
    case package = "Package"
}

extension BuildReport {
    public var schemeName: String { context.scheme ?? context.containerName }
    public var kind: ReportKind { context.kind }
}

public enum ReportNavigatorModel {
    public static let testPages = ["Insights", "Coverage", "Tests", "Log", "Build"]
    public static let recentInterval: TimeInterval = 24 * 3600

    public struct Row: Equatable, Sendable {
        public var title: String
        public var detail: String?
        public var symbol: String
        public var failed: Bool
        public var badge: String?
        public var index: Int
        public var page: String?
        public var children: [Row] = []
    }

    public struct Group: Equatable, Sendable {
        public var title: String
        public var isPackage: Bool
        public var rows: [Row]
    }

    public static func groups(_ reports: [BuildReport], location: ReportLocation = .local, recentOnly: Bool = false,
                              now: Date = Date(), dayAndTime: (Date) -> String = ReportFormat.dayAndTime) -> [Group] {
        let shown = reports.enumerated()
            .filter { $0.element.context.location == location }
            .filter { !recentOnly || now.timeIntervalSince($0.element.date) <= recentInterval }
            .sorted { $0.element.date != $1.element.date ? $0.element.date > $1.element.date : $0.offset < $1.offset }
        var schemes: [Group] = []
        var package = Group(title: "Package", isPackage: true, rows: [])
        for (i, r) in shown {
            let row = self.row(r, index: i, dayAndTime: dayAndTime)
            if r.kind == .package { package.rows.append(row); continue }
            if let g = schemes.firstIndex(where: { $0.title == r.schemeName }) { schemes[g].rows.append(row) }
            else { schemes.append(Group(title: r.schemeName, isPackage: false, rows: [row])) }
        }
        return package.rows.isEmpty ? schemes : schemes + [package]
    }

    static func row(_ r: BuildReport, index i: Int, dayAndTime: (Date) -> String) -> Row {
        let failed = !r.succeeded
        let badge = failed ? "\(max(1, r.errorCount))" : nil
        switch r.kind {
        case .test:
            let children = testPages.map { page -> Row in
                var c = Row(title: page, detail: nil, symbol: symbol(page: page), failed: false, badge: nil, index: i, page: page)
                if page == "Tests" {
                    let n = r.context.tests.filter { $0.status == .failed }.count
                    if n > 0 { c.badge = "\(n)"; c.failed = true }
                }
                if page == "Coverage" { c.detail = CoverageModel.total(r.context.coverage).map(CoverageModel.percent) ?? "—" }
                return c
            }
            return Row(title: "\(r.schemeName)/\(r.context.plan ?? r.schemeName)", detail: dayAndTime(r.date), symbol: "checkmark.diamond",
                       failed: failed, badge: badge, index: i, page: nil, children: children)
        case .package:
            return Row(title: r.context.action, detail: dayAndTime(r.date), symbol: "shippingbox", failed: failed, badge: badge, index: i, page: nil)
        default:
            return Row(title: r.context.action, detail: dayAndTime(r.date), symbol: r.kind == .clean ? "trash" : "hammer",
                       failed: failed, badge: badge, index: i, page: nil)
        }
    }

    static func symbol(page: String) -> String {
        switch page {
        case "Insights": "lightbulb"
        case "Coverage": "chart.bar.xaxis"
        case "Tests": "checkmark.diamond"
        default: "doc.plaintext"
        }
    }

    public static func defaultPage(_ r: BuildReport) -> String { r.kind == .test ? "Insights" : "Log" }
}

public struct BuildLogStep: Equatable, Sendable {
    public var title: String
    public var duration: TimeInterval?
    public var issues: [Diagnostic] = []
    public var children: [BuildLogStep] = []
    public var transcript: [String] = []

    public var errorCount: Int { issues.filter { $0.severity == .error }.count + children.reduce(0) { $0 + $1.errorCount } }
    public var warningCount: Int { issues.filter { $0.severity == .warning }.count + children.reduce(0) { $0 + $1.warningCount } }
    public var badge: String? { let n = errorCount + warningCount; return n > 0 ? "\(n)" : nil }
    public var displayTitle: String { duration.map { "\(title)  \(ReportFormat.seconds($0)) seconds" } ?? title }
}

public struct BuildLogSection: Equatable, Sendable {
    public var target: String
    public var steps: [BuildLogStep]
    public var title: String { "Build target \(target)" }
}

public enum BuildLogModel {
    public enum Messages: Int, Sendable { case all = 0, issues = 1, errors = 2 }

    public static func subtitle(_ c: ReportContext) -> String {
        var parts = ["\(c.containerKind) \(c.containerName)", "Configuration \(c.configuration)"]
        if !c.destination.isEmpty { parts.append("Destination \(c.destination)") }
        if !c.sdk.isEmpty { parts.append("SDK \(c.sdk)") }
        return parts.joined(separator: " | ")
    }

    public static func footer(_ r: BuildReport) -> (String, String) {
        let verb = r.kind == .clean ? "Clean" : "Build"
        let first = "\(verb) \(r.succeeded ? "succeeded" : "failed") \(ReportFormat.footerDate(r.date))  \(ReportFormat.seconds(r.context.duration)) seconds"
        let e = r.errorCount, w = r.warningCount
        return (first, "\(e) error\(e == 1 ? "" : "s"), \(w) warning\(w == 1 ? "" : "s")")
    }

    public static func sections(_ r: BuildReport) -> [BuildLogSection] {
        let fallback = r.context.scheme ?? r.context.containerName
        var sections: [BuildLogSection] = []
        var current: (section: Int, step: Int)?
        func section(_ target: String) -> Int {
            if let i = sections.firstIndex(where: { $0.target == target }) { return i }
            sections.append(BuildLogSection(target: target, steps: []))
            return sections.count - 1
        }
        let times = r.context.logTimes.count == r.log.count ? r.context.logTimes : nil
        var open: (section: Int, step: Int, start: TimeInterval)?
        func close(at end: TimeInterval) {
            guard let o = open else { return }
            let d = max(0, end - o.start)
            sections[o.section].steps[o.step].duration = d
            sections[o.section].steps[o.step].children[0].duration = d
            open = nil
        }
        for (index, line) in r.log.enumerated() {
            if let d = DiagnosticParser.parseLine(line), d.severity != .note {
                let file = d.location.map { URL(fileURLWithPath: $0.file).lastPathComponent }
                var at: (Int, Int)?
                if let file {
                    outer: for (si, s) in sections.enumerated() {
                        for (ti, t) in s.steps.enumerated() where t.children.first?.title.split(separator: " ").contains(Substring(file)) == true { at = (si, ti); break outer }
                    }
                }
                if let (si, ti) = at ?? current.map({ ($0.section, $0.step) }) {
                    sections[si].steps[ti].children[0].issues.append(d)
                    sections[si].steps[ti].children[0].transcript.append(line)
                } else {
                    let si = section(fallback)
                    if let ii = sections[si].steps.firstIndex(where: { $0.title == "Issues" }) { sections[si].steps[ii].issues.append(d) }
                    else { sections[si].steps.append(BuildLogStep(title: "Issues", issues: [d])) }
                }
                continue
            }
            if let (target, group, task, duration) = task(line, isPackage: r.context.containerKind == "Package") {
                let si = section(target)
                if Self.isProgressLine(line) {
                    if let ti = sections[si].steps.firstIndex(where: { $0.title == group }) {
                        sections[si].steps[ti].children[0].transcript.append(line)
                    } else {
                        var t = BuildLogStep(title: task, duration: nil)
                        t.transcript = [line]
                        sections[si].steps.append(BuildLogStep(title: group, duration: nil, children: [t]))
                    }
                    current = nil
                    continue
                }
                var t = BuildLogStep(title: task, duration: duration)
                t.transcript = [line]
                sections[si].steps.append(BuildLogStep(title: group, duration: duration, children: [t]))
                current = (si, sections[si].steps.count - 1)
                if let times, duration == nil {
                    close(at: times[index])
                    open = (si, sections[si].steps.count - 1, times[index])
                }
                continue
            }
            if let (si, ti) = current.map({ ($0.section, $0.step) }), !line.trimmingCharacters(in: .whitespaces).isEmpty {
                sections[si].steps[ti].children[0].transcript.append(line)
            }
        }
        if times != nil { close(at: max(r.context.duration, open?.start ?? 0)) }
        if sections.isEmpty { sections = [BuildLogSection(target: fallback, steps: [])] }
        return sections
    }

    public static func merge(_ recent: [BuildLogSection], _ carried: [BuildLogSection]) -> [BuildLogSection] {
        var out = recent
        for c in carried {
            let i = out.firstIndex { $0.target == c.target } ?? {
                out.append(BuildLogSection(target: c.target, steps: []))
                return out.count - 1
            }()
            let have = Set(out[i].steps.map(\.title))
            out[i].steps += c.steps.filter { !have.contains($0.title) && $0.title != "Issues" }
        }
        return out.filter { !$0.steps.isEmpty || out.count == 1 }
    }

    public static func carriedOver(from previous: BuildReport, into current: BuildReport) -> [BuildLogSection] {
        let all = merge(sections(previous), previous.context.carriedOver)
        let now = sections(current)
        return all.compactMap { s in
            let ran = Set(now.first { $0.target == s.target }?.steps.map(\.title) ?? [])
            let steps = s.steps.filter { !ran.contains($0.title) && $0.title != "Issues" }
            return steps.isEmpty ? nil : BuildLogSection(target: s.target, steps: steps)
        }
    }

    static func isProgressLine(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("["), let close = s.firstIndex(of: "]") else { return false }
        let inside = s[s.index(after: s.startIndex)..<close]
        let parts = inside.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        return inside.contains(where: \.isWhitespace) && parts.count == 2 && parts.allSatisfy { Int($0) != nil }
    }

    static func task(_ line: String, isPackage: Bool) -> (String, String, String, TimeInterval?)? {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            let words = s[s.index(after: close)...].split(separator: " ").map(String.init)
            let progressWords = s[s.index(after: close)...].split(whereSeparator: \.isWhitespace)
            if isProgressLine(s), progressWords.count == 1 {
                let name = String(progressWords[0])
                if name.hasSuffix("-product") {
                    let product = String(name.dropLast("-product".count))
                    return (name, "Linking \(product)", "Link \(product)", nil)
                }
                return (name, "Building \(name)", "Build \(name)", nil)
            }
            guard words.count >= 2 else { return nil }
            switch words[0] {
            case "Compiling" where words.count >= 3:
                let files = words.dropFirst(2).joined(separator: " ")
                return (words[1], "Compiling \(files)", "Compile \(files)", nil)
            case "Emitting" where words.count >= 3 && words[1] == "module":
                return (words[2], "Emitting module \(words[2])", "Emit module \(words[2])", nil)
            case "Linking":
                let name = URL(fileURLWithPath: words[1]).lastPathComponent
                return (isPackage ? "\(name)-product" : name, "Linking \(name)", "Link \(name)", nil)
            case "Write", "Writing", "Applying", "Planning", "Build", "Compiled": return nil
            default: return nil
            }
        }
        if s.hasPrefix("Linking ") {
            let name = URL(fileURLWithPath: String(s.dropFirst(8))).lastPathComponent
            return (isPackage ? "\(name)-product" : name, "Linking \(name)", "Link \(name)", nil)
        }
        guard let r = s.range(of: " (in target '") else { return nil }
        let rest = s[r.upperBound...]
        guard let q = rest.firstIndex(of: "'") else { return nil }
        let target = String(rest[..<q])
        let words = s[..<r.lowerBound].split(separator: " ").map(String.init)
        guard let cmd = words.first else { return nil }
        let object = words.last.map { URL(fileURLWithPath: $0.replacingOccurrences(of: "\\ ", with: " ")).lastPathComponent } ?? ""
        switch cmd {
        case "CompileSwift", "SwiftCompile", "CompileC":
            return (target, "Compiling \(object)", "Compile \(object)", nil)
        case "Ld": return (target, "Linking \(object)", "Link \(object)", nil)
        case "CodeSign": return (target, "Signing \(object)", "Sign \(object)", nil)
        case "CopySwiftLibs", "Copy", "CpResource": return (target, "Copying \(object)", "Copy \(object)", nil)
        case "SwiftEmitModule", "EmitSwiftModule": return (target, "Emitting module \(target)", "Emit module \(target)", nil)
        default: return (target, "\(cmd) \(object)", "\(cmd) \(object)", nil)
        }
    }

    public static func filter(_ sections: [BuildLogSection], messages: Messages, text: String = "") -> [BuildLogSection] {
        func keep(_ step: BuildLogStep) -> BuildLogStep? {
            var s = step
            if messages == .errors { s.issues = s.issues.filter { $0.severity == .error } }
            if !text.isEmpty, !s.title.localizedCaseInsensitiveContains(text) {
                s.issues = s.issues.filter { $0.message.localizedCaseInsensitiveContains(text) }
            }
            s.children = s.children.compactMap(keep)
            let textOK = text.isEmpty || s.title.localizedCaseInsensitiveContains(text) || !s.issues.isEmpty || !s.children.isEmpty
            let kindOK: Bool = switch messages {
            case .all: true
            case .issues: s.errorCount + s.warningCount > 0
            case .errors: s.errorCount > 0
            }
            return textOK && kindOK ? s : nil
        }
        return sections.compactMap { sec in
            let steps = sec.steps.compactMap(keep)
            return steps.isEmpty && messages != .all ? nil : BuildLogSection(target: sec.target, steps: steps)
        }
    }

    public static func outline(_ sections: [BuildLogSection]) -> [String] {
        var out: [String] = []
        func add(_ s: BuildLogStep, _ depth: Int) {
            out.append(String(repeating: "  ", count: depth) + s.displayTitle + (s.badge.map { "  [\($0)]" } ?? ""))
            for c in s.children { add(c, depth + 1) }
            for i in s.issues { out.append(String(repeating: "  ", count: depth + 1) + "\(i.severity == .error ? "error" : "warning"): \(i.message)") }
        }
        for sec in sections {
            out.append(sec.title)
            sec.steps.forEach { add($0, 1) }
        }
        return out
    }
}

public struct CoverageItem: Equatable, Sendable {
    public var name: String
    public var coveredLines: Int
    public var executableLines: Int
    public var files: [CoverageItem] = []
    public var path: String?
    public var lineCounts: [Int]?
    public init(name: String, coveredLines: Int, executableLines: Int, files: [CoverageItem] = [], path: String? = nil, lineCounts: [Int]? = nil) {
        self.name = name
        self.coveredLines = coveredLines
        self.executableLines = executableLines
        self.files = files
        self.path = path
        self.lineCounts = lineCounts
    }
    public var fraction: Double { executableLines == 0 ? 0 : Double(coveredLines) / Double(executableLines) }
    public var isTestBundle: Bool { name.hasSuffix("Tests") || name.hasSuffix(".xctest") }
}

public enum CoverageModel {
    public static func percent(_ f: Double) -> String { String(format: "%.1f%%", f * 100) }

    public static func total(_ targets: [CoverageItem]) -> Double? {
        let t = targets.filter { !$0.isTestBundle }
        let exec = t.reduce(0) { $0 + $1.executableLines }
        return exec == 0 ? nil : Double(t.reduce(0) { $0 + $1.coveredLines }) / Double(exec)
    }

    public static func rows(_ targets: [CoverageItem], showTestBundles: Bool, filter: String = "") -> [CoverageItem] {
        targets.filter { showTestBundles || !$0.isTestBundle }.compactMap { t in
            guard !filter.isEmpty, !t.name.localizedCaseInsensitiveContains(filter) else { return t }
            var c = t
            c.files = t.files.filter { $0.name.localizedCaseInsensitiveContains(filter) }
            return c.files.isEmpty ? nil : c
        }
    }

    public static func parseLLVMCovExport(_ data: Data) -> [CoverageItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (root["data"] as? [[String: Any]])?.first,
              let files = first["files"] as? [[String: Any]] else { return [] }
        var targets: [String: [CoverageItem]] = [:]
        var order: [String] = []
        for f in files {
            guard let name = f["filename"] as? String,
                  let lines = ((f["summary"] as? [String: Any])?["lines"]) as? [String: Any],
                  let count = lines["count"] as? Int, let covered = lines["covered"] as? Int else { continue }
            let comps = name.split(separator: "/").map(String.init)
            guard let i = comps.lastIndex(where: { $0 == "Sources" || $0 == "Tests" }), i + 1 < comps.count - 1 else { continue }
            let target = comps[i + 1]
            if targets[target] == nil { order.append(target) }
            let counts = (f["segments"] as? [[Any]]).map { Coverage.lineCounts(llvmCovSegments: $0) }
            targets[target, default: []].append(CoverageItem(name: comps.last!, coveredLines: covered, executableLines: count, path: name, lineCounts: counts))
        }
        return order.map { t in
            let fs = targets[t]!
            return CoverageItem(name: t, coveredLines: fs.reduce(0) { $0 + $1.coveredLines }, executableLines: fs.reduce(0) { $0 + $1.executableLines }, files: fs)
        }
    }
}

extension CoverageModel {
    public static func parseSwiftCodebuildSummary(_ data: Data) -> [CoverageItem] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targets = root["targets"] as? [[String: Any]] else { return [] }
        return targets.compactMap { t in
            guard let name = t["name"] as? String else { return nil }
            let files = (t["files"] as? [[String: Any]] ?? []).compactMap { f -> CoverageItem? in
                guard let path = f["path"] as? String else { return nil }
                return CoverageItem(name: URL(fileURLWithPath: path).lastPathComponent, coveredLines: f["coveredLines"] as? Int ?? 0,
                                    executableLines: f["executableLines"] as? Int ?? 0, path: path, lineCounts: f["lines"] as? [Int])
            }
            return CoverageItem(name: name, coveredLines: t["coveredLines"] as? Int ?? 0, executableLines: t["executableLines"] as? Int ?? 0, files: files)
        }
    }
}

public enum TestReportModel {
    public struct Summary: Equatable, Sendable {
        public var title: String
        public var builtWith: String
        public var started: String
        public var total: String
        public var passed: Int
        public var failed: Int
        public var configurations: [ConfigurationRow]
        public var failuresHeader: String
        public var failures: [String]
    }

    public struct ConfigurationRow: Equatable, Sendable {
        public var name: String
        public var passed: Int
        public var failed: Int
        public var isDevice: Bool
        public var passedShare: Double { passed + failed == 0 ? 0 : Double(passed) / Double(passed + failed) }
        public var failedShare: Double { passed + failed == 0 ? 0 : Double(failed) / Double(passed + failed) }
    }

    static func counts(_ c: ReportContext) -> (Int, Int) {
        (c.tests.filter { $0.status == .passed }.count, c.tests.filter { $0.status == .failed }.count)
    }

    public static func title(_ r: BuildReport) -> String { "\(r.schemeName)/\(r.context.plan ?? r.schemeName)" }

    public static func summary(_ r: BuildReport) -> Summary {
        let c = r.context
        let (p, f) = counts(c)
        let day = DateFormatter.localizedString(from: r.date, dateStyle: .medium, timeStyle: .none)
        let time = DateFormatter.localizedString(from: r.date, dateStyle: .none, timeStyle: .short)
        let device = c.destination.isEmpty ? "My Mac" : c.destination
        let platform = c.sdk.isEmpty ? device : c.sdk
        let failing = c.tests.filter { $0.status == .failed }
        let n = failing.count
        return Summary(title: title(r), builtWith: "Built with \(platform)",
                       started: "Started \(day) at \(time) · Ran for \(ReportFormat.seconds(c.duration)) seconds",
                       total: "\(p + f) Test\(p + f == 1 ? "" : "s")", passed: p, failed: f,
                       configurations: [ConfigurationRow(name: c.sdk.isEmpty ? device : "\(device) \(c.sdk)", passed: p, failed: f, isDevice: true),
                                        ConfigurationRow(name: "Test Scheme Action", passed: p, failed: f, isDevice: false)],
                       failuresHeader: "Test Failures  \(n) total failure\(n == 1 ? "" : "s")",
                       failures: failing.map { "\($0.name)()  \(splitExpansion($0.failures.first?.message ?? "").0)" })
    }

    public static func testsHeader(_ r: BuildReport) -> String {
        let (p, f) = counts(r.context)
        let k = max(1, r.context.testTargets)
        return "\(f) failed and \(p) passed · Test plan with \(k) test target\(k == 1 ? "" : "s")"
    }

    public static func filterTitles(_ r: BuildReport) -> [String] {
        let (_, f) = counts(r.context)
        return ["Failed Tests (\(f))", "Failed Runs (\(f))", r.context.destination.isEmpty ? "My Mac" : r.context.destination,
                "Test Scheme Action", "Untagged Tests"]
    }

    public struct TestRow: Equatable, Sendable {
        public enum Kind: Sendable { case target, suite, test, failure, expansion }
        public var kind: Kind
        public var title: String
        public var duration: String?
        public var status: TestOutcome.Status?
        public var depth: Int
    }

    public static func duration(_ s: TimeInterval) -> String {
        var t = String(format: "%.5g", s)
        if t.contains("e") { t = String(format: "%.6f", s) }
        return t + "s"
    }

    public static func testRows(_ r: BuildReport, failedOnly: Bool = false, text: String = "") -> [TestRow] {
        let c = r.context
        let tests = c.tests.filter { (!failedOnly || $0.status == .failed) && (text.isEmpty || $0.name.localizedCaseInsensitiveContains(text)) }
        guard !tests.isEmpty else { return [] }
        var rows = [TestRow(kind: .target, title: c.testTarget ?? "\(r.schemeName)Tests", duration: nil, status: nil, depth: 0)]
        var suites: [String?] = []
        for t in tests where !suites.contains(t.suite) { suites.append(t.suite) }
        for s in suites {
            let depth = s == nil ? 1 : 2
            if let s { rows.append(TestRow(kind: .suite, title: s, duration: nil, status: nil, depth: 1)) }
            for t in tests where t.suite == s {
                rows.append(TestRow(kind: .test, title: "\(t.name)()", duration: t.duration.map(duration), status: t.status, depth: depth))
                for f in t.failures {
                    let (message, expansion) = splitExpansion(f.message)
                    let loc = f.location.map { "\(URL(fileURLWithPath: $0.file).lastPathComponent):\($0.line): " } ?? ""
                    rows.append(TestRow(kind: .failure, title: loc + message, duration: nil, status: .failed, depth: depth + 1))
                    if let expansion { rows.append(TestRow(kind: .expansion, title: expansion, duration: nil, status: nil, depth: depth + 1)) }
                }
            }
        }
        return rows
    }

    static func splitExpansion(_ m: String) -> (String, String?) {
        let lines = m.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard lines.count > 1 else { return (m, nil) }
        return (lines[0], lines.dropFirst().joined(separator: " "))
    }
}
