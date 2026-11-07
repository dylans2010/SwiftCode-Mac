import Foundation

public struct TestCaseResult: Equatable, Sendable {
    public enum Library: String, Sendable { case xctest = "XCTest", swiftTesting = "Swift Testing" }
    public enum Status: String, Sendable { case passed = "Success", failed = "Failure", skipped = "Skipped", expectedFailure = "Expected Failure" }
    public struct Issue: Equatable, Sendable {
        public var message: String
        public var file: String?
        public var line: Int?
    }

    public var library: Library
    public var module: String
    public var suite: String
    public var name: String
    public var status: Status
    public var duration: Double
    public var issues: [Issue] = []
    public var skipMessage: String?
    public var skipFile: String?
    public var skipLine: Int?
    public struct Argument: Equatable, Sendable {
        public var label: String
        public var value: String
    }
    public var arguments: [Argument] = []

    public var identifier: String {
        let n = library == .xctest ? name + "()" : name
        return suite.isEmpty ? n : suite + "/" + n
    }

    public var failingName: String { identifier.replacingOccurrences(of: "/", with: ".") }
}

public struct TestConsoleParser {
    public private(set) var results: [TestCaseResult] = []
    var module: String
    var swiftTests: [SwiftTestingBridge.TestRecord]
    var pendingXCTestIssues: [String: [TestCaseResult.Issue]] = [:]
    var pendingXCTestSkips: [String: (message: String, file: String?, line: Int?)] = [:]
    var pendingSwiftIssues: [String: [TestCaseResult.Issue]] = [:]
    var detailTarget: String?
    var detailLines = 0

    public init(module: String, swiftTests: [SwiftTestingBridge.TestRecord]) {
        self.module = module
        self.swiftTests = swiftTests
    }

    public mutating func addSwiftTest(_ r: SwiftTestingBridge.TestRecord) {
        if !swiftTests.contains(where: { $0.id == r.id }) { swiftTests.append(r) }
    }

    static let caseLine = try! NSRegularExpression(pattern: #"^Test Case '-\[([^ \]]+) ([^\]]+)\]' (passed|failed|skipped) \(([0-9.]+) seconds\)\.$"#)
    static let issueLine = try! NSRegularExpression(pattern: #"^(.*):(\d+): (error: )?-\[([^ \]]+) ([^\]]+)\] : (.*)$"#)
    static let swiftDone = try! NSRegularExpression(pattern: #"^. Test (.+?)(?: with \d+ test cases?)? (passed|failed) after ([0-9.]+) seconds"#)
    static let swiftIssue = try! NSRegularExpression(pattern: #"^. Test (.+?) recorded an issue at ([^:]+):(\d+):(\d+): (.*)$"#)
    static let swiftSkip = try! NSRegularExpression(pattern: #"^. Test (.+?) skipped(?:: "(.*)")?\.?$"#)
    static let suiteStarted = try! NSRegularExpression(pattern: #"^. Suite (.+) started\.$"#)
    static let caseStarted = try! NSRegularExpression(pattern: #"^. Test case passing (\d+) arguments? (.+) to (.+) started\.$"#)

    static let testStarted = try! NSRegularExpression(pattern: #"^. Test (.+) started\.$"#)

    public private(set) var startedSuites: [String] = []
    var pendingCases: [String: [[TestCaseResult.Argument]]] = [:]
    var startEvents = 0
    var testStarts: [String: Int] = [:]
    var caseStarts: [String: Int] = [:]

    public func startIndex(of function: String) -> Int {
        caseStarts[function] ?? testStarts[function] ?? Int.max
    }

    static func arguments(_ text: String) -> [TestCaseResult.Argument] {
        text.components(separatedBy: ", ").compactMap { part in
            guard let r = part.range(of: " → ") else { return nil }
            return TestCaseResult.Argument(label: String(part[..<r.lowerBound]), value: String(part[r.upperBound...]))
        }
    }

    static func groups(_ re: NSRegularExpression, _ s: String) -> [String?]? {
        let ns = s as NSString
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (1..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? nil : ns.substring(with: m.range(at: $0)) }
    }

    func classPart(_ qualified: String) -> String {
        qualified.hasPrefix(module + ".") ? String(qualified.dropFirst(module.count + 1)) : qualified
    }

    public mutating func feed(_ raw: String) {
        let line = raw.replacingOccurrences(of: "\u{200B}", with: "")
        if line.hasPrefix("↳"), let name = detailTarget, var list = pendingSwiftIssues[name], !list.isEmpty {
            detailLines += 1
            if detailLines > 1 {
                list[list.count - 1].message += "\n" + line.dropFirst().trimmingCharacters(in: .whitespaces)
                pendingSwiftIssues[name] = list
            }
            return
        }
        detailTarget = nil
        if let g = Self.groups(Self.caseLine, line), let cls = g[0], let method = g[1], let status = g[2] {
            let key = cls + " " + method
            var r = TestCaseResult(library: .xctest, module: module, suite: classPart(cls), name: method,
                                   status: status == "passed" ? .passed : status == "failed" ? .failed : .skipped,
                                   duration: Double(g[3] ?? "0") ?? 0)
            r.issues = pendingXCTestIssues.removeValue(forKey: key) ?? []
            if let skip = pendingXCTestSkips.removeValue(forKey: key) {
                r.skipMessage = skip.message
                r.skipFile = skip.file
                r.skipLine = skip.line
            }
            results.append(r)
            return
        }
        if let g = Self.groups(Self.issueLine, line), let cls = g[3], let method = g[4], let message = g[5] {
            let key = cls + " " + method
            if g[2] == nil, message.hasPrefix("Test skipped") {
                pendingXCTestSkips[key] = (message.hasPrefix("Test skipped - ") ? String(message.dropFirst("Test skipped - ".count)) : "",
                                           g[0], g[1].flatMap { Int($0) })
            } else {
                pendingXCTestIssues[key, default: []].append(.init(message: message, file: g[0], line: g[1].flatMap { Int($0) }))
            }
            return
        }
        if let g = Self.groups(Self.swiftIssue, line), let name = g[0], let file = g[1], let message = g[4] {
            pendingSwiftIssues[name, default: []].append(.init(message: message, file: file, line: g[2].flatMap { Int($0) }))
            detailTarget = name
            detailLines = 0
            return
        }
        if let g = Self.groups(Self.suiteStarted, line), let name = g[0] {
            if !startedSuites.contains(name) { startedSuites.append(name) }
            return
        }
        if let g = Self.groups(Self.caseStarted, line), let args = g[1], let name = g[2] {
            pendingCases[name, default: []].append(Self.arguments(args))
            startEvents += 1
            if caseStarts[name] == nil { caseStarts[name] = startEvents }
            return
        }
        if let g = Self.groups(Self.testStarted, line), let name = g[0] {
            startEvents += 1
            if testStarts[name] == nil { testStarts[name] = startEvents }
            return
        }
        if let g = Self.groups(Self.swiftDone, line), let name = g[0], !name.hasPrefix("run with"), let status = g[1] {
            var issues = pendingSwiftIssues.removeValue(forKey: name) ?? []
            let record = swiftRecord(named: name, file: issues.first?.file)
            if let full = record?.file {
                for i in issues.indices where issues[i].file == URL(fileURLWithPath: full).lastPathComponent { issues[i].file = full }
            }
            let base = TestCaseResult(library: .swiftTesting, module: module, suite: record.map(suitePath) ?? "",
                                      name: record?.name ?? name, status: status == "passed" ? .passed : .failed,
                                      duration: Double(g[2] ?? "0") ?? 0, issues: issues)
            let cases = pendingCases.removeValue(forKey: name) ?? []
            if cases.count > 1 || (cases.count == 1 && !cases[0].isEmpty) {
                for c in cases {
                    var r = base
                    r.arguments = c
                    r.duration = base.duration / Double(cases.count)
                    results.append(r)
                }
            } else {
                results.append(base)
            }
            return
        }
        if let g = Self.groups(Self.swiftSkip, line), let name = g[0], !name.hasPrefix("run") {
            let record = swiftRecord(named: name, file: nil)
            var r = TestCaseResult(library: .swiftTesting, module: module, suite: record.map(suitePath) ?? "",
                                   name: record?.name ?? name, status: .skipped, duration: 0)
            r.skipMessage = g[1]
            results.append(r)
        }
    }

    func suitePath(_ r: SwiftTestingBridge.TestRecord) -> String {
        let p = r.path
        guard let slash = p.lastIndex(of: "/") else { return "" }
        return String(p[..<slash])
    }

    func swiftRecord(named name: String, file: String?) -> SwiftTestingBridge.TestRecord? {
        let candidates = swiftTests.filter { !$0.isSuite && $0.name == name }
        if candidates.count <= 1 { return candidates.first }
        if let file {
            if let r = candidates.first(where: { ($0.file.map { URL(fileURLWithPath: $0).lastPathComponent }) == file }) { return r }
        }
        return candidates.first
    }
}
