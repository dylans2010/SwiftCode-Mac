#if canImport(Darwin)
import Darwin
import Foundation
import MachO
import ObjectiveC

@_cdecl("swiftcode_test_agent_start")
public func swiftcodeTestAgentStart() {
    TestAgent.shared.start()
}

final class TestAgent: @unchecked Sendable {
    static let shared = TestAgent()

    static let prefix = "##swiftcode-test## "

    private var started = false
    private var session = ""
    private var bundles: [BundleRun] = []
    private var current = BundleRun(path: "", module: "", only: [], skip: [])
    private var only: [String] { current.only }
    private var skip: [String] { current.skip }
    private var repetition = Repetition(mode: .once, count: 1)
    private var failed = false
    private var counts: [String: Int] = ["passed": 0, "failed": 0, "skipped": 0]
    private var observer: AnyObject?
    private var launchObservers: [NSObjectProtocol] = []

    struct BundleRun {
        var path: String
        var module: String
        var only: [String]
        var skip: [String]
    }

    struct Repetition {
        enum Mode: String { case once, fixed = "fixedIterations", untilFailure, retryOnFailure }
        var mode: Mode
        var count: Int
    }

    func start() {
        let env = ProcessInfo.processInfo.environment
        guard let text = env["SWIFTCODE_TEST_PLAN"], let plan = Self.object(text) else { return }
        session = plan["session"] as? String ?? ""
        bundles = (plan["bundles"] as? [[String: Any]] ?? []).compactMap { b in
            guard let path = b["path"] as? String else { return nil }
            return BundleRun(path: path, module: b["module"] as? String ?? "", only: b["only"] as? [String] ?? [], skip: b["skip"] as? [String] ?? [])
        }
        if let r = plan["repetition"] as? [String: Any], let mode = (r["mode"] as? String).flatMap(Repetition.Mode.init(rawValue:)) {
            repetition = Repetition(mode: mode, count: max(1, r["count"] as? Int ?? 1))
        }
        unsetenv("DYLD_INSERT_LIBRARIES")
        unsetenv("SWIFTCODE_TEST_PLAN")
        report(["kind": "agentLoaded", "pid": Int(getpid()), "host": CommandLine.arguments.first ?? ""])
        let center = NotificationCenter.default
        for name in ["NSApplicationDidFinishLaunchingNotification", "UIApplicationDidFinishLaunchingNotification"] {
            guard let value = Self.exportedString(name) else { continue }
            launchObservers.append(center.addObserver(forName: Notification.Name(value), object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.begin(reason: "launched") }
            })
        }
        let wait = plan["launchTimeout"] as? Double ?? 30
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in self?.begin(reason: "timeout") }
    }

    static func exportedString(_ symbol: String) -> String? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) else { return nil }
        let ref = p.assumingMemoryBound(to: Unmanaged<NSString>?.self).pointee
        return ref?.takeUnretainedValue() as String?
    }

    static func object(_ json: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

    func report(_ fields: [String: Any]) {
        var all = fields
        all["v"] = 1
        if !session.isEmpty { all["session"] = session }
        guard let data = try? JSONSerialization.data(withJSONObject: all, options: [.sortedKeys]) else { return }
        var bytes = Array(Self.prefix.utf8)
        bytes += data
        bytes.append(0x0A)
        fflush(stdout)
        bytes.withUnsafeBytes { _ = write(STDERR_FILENO, $0.baseAddress, $0.count) }
    }

    func finish(_ status: Int32) {
        report(["kind": "runFinished", "status": status == 0 ? "passed" : "failed", "exitCode": Int(status),
                "passed": counts["passed"] ?? 0, "failed": counts["failed"] ?? 0, "skipped": counts["skipped"] ?? 0])
        fflush(stdout)
        fflush(stderr)
        exit(status)
    }

    func count(_ status: String) {
        counts[status, default: 0] += 1
    }

    private func begin(reason: String) {
        guard !started else { return }
        started = true
        report(["kind": "runStarted", "reason": reason, "bundles": bundles.count])
        runNext(0, loadFailed: false)
    }

    private func runNext(_ index: Int, loadFailed: Bool) {
        guard index < bundles.count else { return finish(loadFailed ? 70 : failed ? 1 : 0) }
        current = bundles[index]
        report(["kind": "bundleStarted", "path": current.path, "module": current.module])
        guard let bundle = loadBundle() else {
            report(["kind": "bundleFinished", "path": current.path, "loaded": false])
            return runNext(index + 1, loadFailed: true)
        }
        if current.module.isEmpty { current.module = bundle.executableURL?.lastPathComponent ?? "" }
        let xctests = runXCTest(bundle)
        guard xctests == 0 || Self.hasSwiftTestContent(bundle), let entry = swiftTestingEntryPoint(bundle) else {
            report(["kind": "bundleFinished", "path": current.path, "loaded": true])
            return runNext(index + 1, loadFailed: loadFailed)
        }
        let config = (try? JSONSerialization.data(withJSONObject: swiftTestingConfiguration(module: current.module))) ?? Data("{}".utf8)
        report(["kind": "phase", "framework": "Swift Testing"])
        Task { @Sendable in
            let ok = await self.runSwiftTesting(entry, config)
            DispatchQueue.main.async {
                if !ok { self.failed = true }
                self.report(["kind": "bundleFinished", "path": self.current.path, "loaded": true])
                self.runNext(index + 1, loadFailed: loadFailed)
            }
        }
    }

    func bundlePath() -> String {
        let spec = current.path
        if spec.hasPrefix("/") { return spec }
        if spec.hasPrefix("@executable_path/") {
            let exe = Bundle.main.executableURL?.deletingLastPathComponent().path ?? ""
            return exe + "/" + spec.dropFirst("@executable_path/".count)
        }
        return (Bundle.main.builtInPlugInsPath ?? Bundle.main.bundlePath + "/PlugIns") + "/" + spec
    }

    func loadBundle() -> Bundle? {
        let path = bundlePath()
        guard let bundle = Bundle(path: path) else {
            report(["kind": "error", "message": "There is no test bundle at \(path)."])
            return nil
        }
        do { try bundle.loadAndReturnError() } catch {
            report(["kind": "error", "message": "The test bundle \(path) could not be loaded: \(error)"])
            return nil
        }
        report(["kind": "bundleLoaded", "path": path])
        return bundle
    }

    typealias Send0 = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    typealias Send1 = @convention(c) (AnyObject, Selector, AnyObject) -> Unmanaged<AnyObject>?
    typealias SendVoid = @convention(c) (AnyObject, Selector) -> Void
    typealias SendVoid1 = @convention(c) (AnyObject, Selector, AnyObject) -> Void

    static func call(_ target: AnyObject, _ name: String) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let m = class_getMethodImplementation(object_getClass(target), sel) else { return nil }
        return unsafeBitCast(m, to: Send0.self)(target, sel)?.takeUnretainedValue()
    }

    static func call(_ target: AnyObject, _ name: String, _ arg: AnyObject) -> AnyObject? {
        let sel = NSSelectorFromString(name)
        guard let m = class_getMethodImplementation(object_getClass(target), sel) else { return nil }
        return unsafeBitCast(m, to: Send1.self)(target, sel, arg)?.takeUnretainedValue()
    }

    static func callVoid(_ target: AnyObject, _ name: String, _ arg: AnyObject? = nil) {
        let sel = NSSelectorFromString(name)
        guard let m = class_getMethodImplementation(object_getClass(target), sel) else { return }
        if let arg { unsafeBitCast(m, to: SendVoid1.self)(target, sel, arg) } else { unsafeBitCast(m, to: SendVoid.self)(target, sel) }
    }

    static func split(testName: String) -> (cls: String, method: String)? {
        guard testName.hasPrefix("-["), testName.hasSuffix("]") else { return nil }
        let inner = testName.dropFirst(2).dropLast()
        guard let space = inner.firstIndex(of: " ") else { return nil }
        return (String(inner[..<space]), String(inner[inner.index(after: space)...]))
    }

    static func bareClass(_ cls: String) -> String {
        cls.split(separator: ".", maxSplits: 1).count == 2 ? String(cls.split(separator: ".", maxSplits: 1)[1]) : cls
    }

    func selects(cls: String, method: String) -> Bool {
        let c = Self.bareClass(cls)
        let ids = [c, c + "/" + method, c + "/" + method + "()"]
        if skip.contains(where: { ids.contains($0) }) { return false }
        return only.isEmpty || only.contains(where: { ids.contains($0) })
    }

    static func testCases(_ test: AnyObject) -> [AnyObject] {
        if let suiteClass: AnyClass = NSClassFromString("XCTestSuite"), (test as? NSObject)?.isKind(of: suiteClass) == true,
           let tests = (test as? NSObject)?.value(forKey: "tests") as? [AnyObject] {
            return tests.flatMap(testCases)
        }
        return [test]
    }

    @discardableResult
    func runXCTest(_ bundle: Bundle) -> Int {
        guard let suiteClass: AnyClass = NSClassFromString("XCTestSuite"),
              let all = Self.call(suiteClass, "testSuiteForBundlePath:", bundle.bundlePath as NSString) else { return 0 }
        let total = Self.testCases(all).count
        let cases = Self.testCases(all).filter { tc in
            guard let name = (tc as? NSObject)?.value(forKey: "name") as? String, let parts = Self.split(testName: name) else { return false }
            return selects(cls: parts.cls, method: parts.method)
        }
        guard !cases.isEmpty else { return total }
        report(["kind": "phase", "framework": "XCTest", "tests": cases.count])
        installObserver()
        let title = only.isEmpty && skip.isEmpty ? "All tests" : "Selected tests"
        var pending = cases
        var round = 0
        var lastFailures: Set<String> = []
        var anyFailure = false
        while !pending.isEmpty, round < repetition.count {
            round += 1
            guard let suite = Self.call(suiteClass, "testSuiteWithName:", title as NSString) else { return total }
            for tc in pending { Self.callVoid(suite, "addTest:", tc) }
            if repetition.mode != .once { report(["kind": "iteration", "framework": "XCTest", "iteration": round]) }
            roundFailures = []
            Self.callVoid(suite, "runTest")
            anyFailure = anyFailure || !roundFailures.isEmpty
            lastFailures = lastFailures.subtracting(pending.compactMap(Self.name)).union(roundFailures)
            switch repetition.mode {
            case .once: pending = []
            case .fixed: break
            case .untilFailure: if !roundFailures.isEmpty { pending = [] }
            case .retryOnFailure: pending = pending.filter { roundFailures.contains(Self.name($0) ?? "") }
            }
            if round < repetition.count { pending = pending.compactMap(Self.freshCase) }
        }
        if repetition.mode == .retryOnFailure ? !lastFailures.isEmpty : anyFailure { failed = true }
        return total
    }

    static func hasSwiftTestContent(_ bundle: Bundle) -> Bool {
        guard let exe = bundle.executableURL?.resolvingSymlinksInPath().path else { return false }
        for i in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(i), URL(fileURLWithPath: String(cString: name)).resolvingSymlinksInPath().path == exe,
                  let header = _dyld_get_image_header(i) else { continue }
            var size: UInt = 0
            let mh = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
            return getsectiondata(mh, "__DATA_CONST", "__swift5_tests", &size) != nil && size > 0
        }
        return false
    }

    static func name(_ tc: AnyObject) -> String? { (tc as? NSObject)?.value(forKey: "name") as? String }

    var roundFailures: Set<String> = []

    static func freshCase(_ tc: AnyObject) -> AnyObject? {
        guard let parts = name(tc).flatMap(split(testName:)), let cls = object_getClass(tc) else { return tc }
        let sendSel = NSSelectorFromString("testCaseWithSelector:")
        guard let m = class_getMethodImplementation(object_getClass(cls), sendSel) else { return tc }
        typealias F = @convention(c) (AnyClass, Selector, Selector) -> Unmanaged<AnyObject>?
        return unsafeBitCast(m, to: F.self)(cls, sendSel, NSSelectorFromString(parts.method))?.takeUnretainedValue() ?? tc
    }

    func installObserver() {
        guard observer == nil, let centerClass: AnyClass = NSClassFromString("XCTestObservationCenter"),
              let center = Self.call(centerClass, "sharedTestObservationCenter") else { return }
        if let proto = objc_getProtocol("XCTestObservation") { class_addProtocol(XCTestReporter.self, proto) }
        let o = XCTestReporter(agent: self)
        observer = o
        Self.callVoid(center, "addTestObserver:", o)
    }

    typealias EntryPoint = @convention(thin) @Sendable (
        _ configurationJSON: UnsafeRawBufferPointer?,
        _ recordHandler: @escaping @Sendable (_ recordJSON: UnsafeRawBufferPointer) -> Void
    ) async throws -> Bool

    func swiftTestingEntryPoint(_ bundle: Bundle) -> EntryPoint? {
        let handle = bundle.executableURL.flatMap { dlopen($0.path, RTLD_NOW | RTLD_NOLOAD) }
        guard let symbol = handle.flatMap({ dlsym($0, "swt_abiv0_getEntryPoint") }) ?? dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swt_abiv0_getEntryPoint") else {
            return nil
        }
        typealias Getter = @convention(c) () -> UnsafeRawPointer
        return unsafeBitCast(unsafeBitCast(symbol, to: Getter.self)(), to: EntryPoint.self)
    }

    func swiftTestingConfiguration(module: String) -> [String: Any] {
        func pattern(_ id: String) -> String {
            "^" + NSRegularExpression.escapedPattern(for: module + "." + id) + "(/|$)"
        }
        var c: [String: Any] = ["eventStreamVersion": 0]
        let swiftOnly = only.filter { !$0.isEmpty }
        c["filter"] = swiftOnly.isEmpty ? ["^" + NSRegularExpression.escapedPattern(for: module + ".")] : swiftOnly.map(pattern)
        if !skip.isEmpty { c["skip"] = skip.map(pattern) }
        switch repetition.mode {
        case .once: break
        case .fixed: c["repetitions"] = repetition.count
        case .untilFailure: c["repetitions"] = repetition.count; c["repeatUntil"] = "fail"
        case .retryOnFailure: c["repetitions"] = repetition.count; c["repeatUntil"] = "pass"
        }
        return c
    }

    func runSwiftTesting(_ entry: EntryPoint, _ json: Data) async -> Bool {
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: json.count, alignment: 1)
        defer { buffer.deallocate() }
        buffer.copyBytes(from: json)
        let tracker = SwiftTestingTracker(agent: self)
        do {
            let ok = try await entry(UnsafeRawBufferPointer(buffer)) { record in tracker.take(Data(record)) }
            return ok
        } catch {
            report(["kind": "error", "message": "Swift Testing could not run: \(error)"])
            return false
        }
    }
}

final class XCTestReporter: NSObject {
    let agent: TestAgent
    init(agent: TestAgent) { self.agent = agent }

    func names(_ testCase: AnyObject) -> (suite: String, name: String) {
        let full = (testCase as? NSObject)?.value(forKey: "name") as? String ?? ""
        guard let p = TestAgent.split(testName: full) else { return ("", full) }
        return (TestAgent.bareClass(p.cls), p.method)
    }

    @objc func testCaseWillStart(_ testCase: AnyObject) {
        let n = names(testCase)
        agent.report(["kind": "testStarted", "framework": "XCTest", "suite": n.suite, "name": n.name])
    }

    @objc(testCase:didRecordIssue:) func testCase(_ testCase: AnyObject, didRecordIssue issue: AnyObject) {
        let n = names(testCase)
        let o = issue as? NSObject
        var r: [String: Any] = ["kind": "issue", "framework": "XCTest", "suite": n.suite, "name": n.name,
                                "message": o?.value(forKey: "compactDescription") as? String ?? ""]
        if let loc = o?.value(forKeyPath: "sourceCodeContext.location") as? NSObject {
            if let url = loc.value(forKey: "fileURL") as? URL { r["file"] = url.path }
            if let line = loc.value(forKey: "lineNumber") as? Int { r["line"] = line }
        }
        agent.report(r)
    }

    @objc func testCaseDidFinish(_ testCase: AnyObject) {
        let n = names(testCase)
        let run = (testCase as? NSObject)?.value(forKey: "testRun") as? NSObject
        let skipped = run?.value(forKey: "hasBeenSkipped") as? Bool ?? false
        let ok = run?.value(forKey: "hasSucceeded") as? Bool ?? false
        let status = skipped ? "skipped" : ok ? "passed" : "failed"
        if status == "failed" { agent.roundFailures.insert((testCase as? NSObject)?.value(forKey: "name") as? String ?? "") }
        agent.count(status)
        agent.report(["kind": "testFinished", "framework": "XCTest", "suite": n.suite, "name": n.name, "status": status,
                      "duration": run?.value(forKey: "testDuration") as? Double ?? 0])
    }
}

final class SwiftTestingTracker: @unchecked Sendable {
    let agent: TestAgent
    private let lock = NSLock()
    private var tests: [String: (suite: String, name: String, isSuite: Bool)] = [:]
    private var issues: Set<String> = []
    init(agent: TestAgent) { self.agent = agent }

    static func names(id: String, name: String, isSuite: Bool) -> (suite: String, name: String) {
        var parts = id.split(separator: "/").map(String.init)
        if let last = parts.last, last.contains(".swift:") { parts.removeLast() }
        guard let first = parts.first else { return ("", name) }
        let typePath = first.split(separator: ".").dropFirst().map(String.init)
        if isSuite { return (typePath.dropLast().joined(separator: "/"), typePath.last ?? name) }
        return (typePath.joined(separator: "/"), parts.count > 1 ? parts[parts.count - 1] : name)
    }

    func take(_ data: Data) {
        guard let rec = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let payload = rec["payload"] as? [String: Any] else { return }
        lock.lock()
        defer { lock.unlock() }
        if rec["kind"] as? String == "test", let id = payload["id"] as? String {
            let isSuite = payload["kind"] as? String == "suite"
            let n = Self.names(id: id, name: payload["name"] as? String ?? "", isSuite: isSuite)
            tests[id] = (n.suite, n.name, isSuite)
            let loc = payload["sourceLocation"] as? [String: Any]
            var r: [String: Any] = ["kind": "swiftTest", "id": id, "name": payload["name"] as? String ?? "", "isSuite": isSuite]
            if let file = loc?["filePath"] as? String ?? loc?["_filePath"] as? String { r["file"] = file }
            if let line = loc?["line"] as? Int { r["line"] = line }
            agent.report(r)
            return
        }
        guard rec["kind"] as? String == "event", let kind = payload["kind"] as? String,
              let id = payload["testID"] as? String, let t = tests[id], !t.isSuite else { return }
        var r: [String: Any] = ["framework": "Swift Testing", "suite": t.suite, "name": t.name]
        switch kind {
        case "testStarted":
            issues.remove(id)
            r["kind"] = "testStarted"
            if let n = payload["iteration"] as? Int { r["iteration"] = n }
        case "issueRecorded":
            let issue = payload["issue"] as? [String: Any]
            let known = issue?["isKnown"]
            guard issue?["isFailure"] as? Bool ?? true, (known as? Bool) != true, !(known is String) else { return }
            issues.insert(id)
            r["kind"] = "issue"
            r["message"] = ((payload["messages"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
            if let loc = issue?["sourceLocation"] as? [String: Any] ?? payload["sourceLocation"] as? [String: Any] {
                r["file"] = loc["filePath"] as? String ?? loc["_filePath"] as? String
                r["line"] = loc["line"] as? Int
            }
        case "testEnded":
            let status = issues.contains(id) ? "failed" : "passed"
            agent.count(status)
            r["kind"] = "testFinished"
            r["status"] = status
        case "testSkipped":
            agent.count("skipped")
            r["kind"] = "testFinished"
            r["status"] = "skipped"
        default:
            return
        }
        agent.report(r)
    }
}
#endif
