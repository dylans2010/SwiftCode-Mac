import Foundation
import SwiftCodeBuild
import SwiftCodeDebug
import SwiftCodeLanguage
import SwiftCodeProject

@MainActor
public final class WorkspaceSession {
    public enum Activity: Equatable {
        case idle
        case building(String)
        case running(String)
        case paused(String)
        case finished(String)
    }

    public enum Change { case activity, issues, breakpoints, console, debugState, reports, tests, process }

    public var model: WorkspaceModel { didSet { issueTargetStore.targets = [:] } }
    public var scheme: String? { didSet { if scheme != oldValue { buildContextChanged() } } }
    public var destination: Destination? { didSet { if destination?.specifier != oldValue?.specifier { buildContextChanged() } } }
    public var engine: BuildEngine = BuildSystemPreference.current().makeEngine()
    public private(set) var activity: Activity = .idle
    public internal(set) var issues: [Diagnostic] = []
    public internal(set) var failedTestCount = 0
    public internal(set) var runningProduct: String?
    public internal(set) var runningDeviceName: String?
    var runningActivityTitle: String { DebugPresentation.runningTitle(runningProduct, on: runningDeviceName) }
    public var includeLiveIssues = true { didSet { notify(.issues) } }
    public var packageIssues: [Diagnostic] = [] { didSet { notify(.issues) } }
    public internal(set) var projectIssues: [Diagnostic] = []
    public internal(set) var lastTestRun: TestRun?
    public var activeTestPlan: String?
    var repetitionCancelled = false
    public internal(set) var language: LanguageService?
    let languageRestart = LanguageRestartState()

    public var displayedIssues: [Diagnostic] {
        let live = includeLiveIssues ? (language?.liveIssues ?? [:]).keys.sorted().flatMap { language!.liveIssues[$0]! } : []
        return IssueMerge.merge([projectIssues, packageIssues, issues], live: live, liveHiddenFiles: liveIssuesHiddenFiles)
    }

    public var liveIssuesHiddenFiles: Set<String> {
        Set(issues.compactMap { $0.location.map { IssueMerge.canonicalPath($0.file) } }).subtracting(issueEditState.editedSinceBuild)
    }
    final class IssueEditState { var editedSinceBuild = Set<String>() }
    let issueEditState = IssueEditState()

    public func noteFileEdited(_ path: String) {
        let p = IssueMerge.canonicalPath(path)
        let wasHidden = liveIssuesHiddenFiles.contains(p)
        issueEditState.editedSinceBuild.insert(p)
        if wasHidden { notify(.issues) }
    }

    func languageIssuesChanged() { notify(.issues) }

    public var issueGrouping: IssueGrouping {
        let model = self.model
        if model.kind == .package {
            let root = IssueMerge.canonicalPath(model.url.path)
            var order: [String] = []
            for dir in ["Sources", "Tests"] {
                let names = (try? FileManager.default.contentsOfDirectory(atPath: model.url.appendingPathComponent(dir).path)) ?? []
                order += names.filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            }
            return IssueGrouping(projectName: model.displayName, targetOrder: order) { file in
                let p = IssueMerge.canonicalPath(file)
                guard p.hasPrefix(root + "/") else { return [] }
                let parts = p.dropFirst(root.count + 1).split(separator: "/")
                guard parts.count > 2, ["Sources", "Tests"].contains(parts[0]) else { return [] }
                return [String(parts[1])]
            }
        }
        let projects = model.projects.keys.sorted().compactMap { path in model.projects[path].map { (URL(fileURLWithPath: path), $0) } }
        let order = projects.flatMap { $0.1.targets.compactMap { $0.string("name") } }
        let cache = issueTargetStore
        return IssueGrouping(projectName: model.kind == .project ? model.displayName : (projects.first?.0.deletingPathExtension().lastPathComponent ?? model.displayName),
                             targetOrder: order) { file in
            if let hit = cache.targets[file] { return hit }
            let found = projects.flatMap { url, proj in
                proj.targetMemberships(ofFile: file, projectDirectory: proj.projectDirectory(xcodeprojURL: url)).filter(\.isMember).map(\.name)
            }
            cache.targets[file] = found
            return found
        }
    }
    final class IssueTargetCache { var targets: [String: [String]] = [:] }
    let issueTargetStore = IssueTargetCache()
    public var breakpoints = BreakpointStore() {
        didSet {
            notify(.breakpoints)
            breakpointFile?.save(breakpoints)
            Task { await syncBreakpoints() }
        }
    }
    public private(set) var breakpointFile: BreakpointPersistence?

    public func attachBreakpointFile(user: String = NSUserName()) {
        let file = BreakpointPersistence(container: model.url, isPackage: model.kind == .package, user: user)
        breakpointFile = file
        breakpoints = file.load()
    }
    public private(set) var console = ""
    public private(set) var buildLog: [String] = []
    private var buildLogTimes: [TimeInterval] = []
    private var buildLogStarted = Date()
    func appendBuildLog(_ line: String) {
        buildLog.append(line)
        buildLogTimes.append(Date().timeIntervalSince(buildLogStarted))
    }
    func resetBuildLog() {
        buildLog = []
        buildLogTimes = []
        buildLogStarted = Date()
    }
    public private(set) var tests: [DiscoveredTest] = []
    public private(set) var testDiscovery: Task<Void, Never>?
    private var testDiscoveryGeneration = 0
    public internal(set) var testResults: [DiscoveredTest: TestOutcome.Status] = [:]
    public var testRunner = TestRunner()
    public var remoteSimulatorForTests: (@MainActor (Destination) -> RemoteSimulator?)?
    public var buildSystemPreference: BuildSystemPreference = .current()

    @discardableResult
    public func discoverTests() -> Task<Void, Never> {
        testDiscoveryGeneration += 1
        let generation = testDiscoveryGeneration, root = model.root
        let task = Task { [weak self] in
            let found = await Task.detached { TestDiscovery.tests(in: root) }.value
            guard let self, generation == self.testDiscoveryGeneration else { return }
            self.tests = found
            self.testDiscovery = nil
            self.notify(.tests)
        }
        testDiscovery = task
        return task
    }

    public func testsDiscovered() async {
        while let t = testDiscovery { await t.value }
    }

    public func testsForDiamond(file: String, line: Int) -> [DiscoveredTest] {
        if let t = tests.first(where: { $0.file == file && $0.line == line }) { return [t] }
        return tests.filter { $0.file == file && $0.suiteLine == line }
    }

    public func runnerIdentifier(_ t: DiscoveredTest) -> String {
        guard model.kind != .package, let target = model.targetName(compiling: t.file) else { return t.identifier }
        return "\(target)/\(t.identifier)"
    }

    static func sdkName(for destination: String) -> String {
        let lower = destination.lowercased()
        guard destination.isEmpty || lower.contains("mac") else { return "" }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)"
    }

    func reportContext(action: String, started: Date) -> ReportContext {
        var c = ReportContext()
        c.action = action
        c.scheme = scheme
        c.containerKind = model.kind == .package ? "Package" : "Project"
        c.containerName = model.displayName
        let s = scheme.flatMap { name in model.loadSchemes().first { $0.name == name } }
        c.configuration = s?.configuration(for: action == "Test" ? "TestAction" : "LaunchAction") ?? "Debug"
        c.destination = destination?.name ?? ""
        c.sdk = Self.sdkName(for: c.destination)
        c.duration = Date().timeIntervalSince(started)
        if action == "Test" {
            c.plan = effectiveTestPlan
            c.testTargets = max(1, Set(tests.map { model.kind == .package ? URL(fileURLWithPath: $0.file).deletingLastPathComponent().lastPathComponent : (model.targetName(compiling: $0.file) ?? "") }).count)
        }
        return c
    }

    @discardableResult
    public func runTests(only: [DiscoveredTest] = [], withoutBuilding: Bool = false) async -> [TestOutcome] {
        stop()
        lastTestRun = TestRun(tests: only, withoutBuilding: withoutBuilding)
        discoverTests()
        await testsDiscovered()
        resetBuildLog()
        let testStarted = Date()
        let progress = TestActivityProgress(subject: scheme ?? model.displayName)
        testActivityProgress = progress
        setActivity(.building(progress.text))
        let request = model.buildRequest(scheme: scheme, destination: destination, action: withoutBuilding ? .testWithoutBuilding : .test)
        var runner = selectedTestRunner
        runner.coverage = gathersCoverage
        if let d = destination, d.isSwiftCodeRemoteSimulator, let remote = remoteSimulatorForTests?(d) {
            runner.environment.merge(remote.testEnvironment) { _, new in new }
            runner.destinationOverride = RemoteSimulator.testDestination
        }
        let summary = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-coverage-\(UUID().uuidString).json").path
        if runner.coverage { runner.coverageSummaryPath = summary }
        defer { try? FileManager.default.removeItem(atPath: summary) }
        let (code, ran) = await runner.run(request, only: only.map(runnerIdentifier)) { line in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appendBuildLog(line)
                if self.testActivityProgress === progress, let text = progress.feed(line) { self.setActivity(.building(text)) }
            }
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        let outcomes = TestFailureFiles.resolve(ran, tests: tests)
        if testActivityProgress === progress { testActivityProgress = nil }
        for t in (only.isEmpty ? tests : only) {
            testResults[t] = outcomes.first { t.matches($0) }?.status
        }
        let failures = outcomes.flatMap(\.failures)
        issues = failures
        notify(.issues)
        notify(.tests)
        let ok = code == 0 && !outcomes.contains { $0.status == .failed }
        var report = BuildReport(title: "Test \(scheme ?? model.displayName)", date: Date(), succeeded: ok, log: buildLog,
                                 errorCount: outcomes.filter { $0.status == .failed }.count, warningCount: 0)
        report.context = reportContext(action: "Test", started: testStarted)
        report.context.tests = outcomes
        report.context.issues = failures
        report.context.logTimes = buildLogTimes
        if runner.coverage { report.context.coverage = await Task.detached { Self.coverage(request: request, runner: runner, summary: summary) }.value }
        reports.insert(report, at: 0)
        pruneReports()
        notify(.reports)
        failedTestCount = outcomes.filter { $0.status == .failed }.count
        notify(.issues)
        setActivity(.finished(Self.testFinishedText(selected: !only.isEmpty, passed: ok)))
        return outcomes
    }

    public static func testFinishedText(selected: Bool, passed: Bool) -> String {
        if selected { return RunActivityText.testCompleted }
        return passed ? RunActivityText.testSucceeded : RunActivityText.testFailed
    }

    package var testActivityProgress: TestActivityProgress?

    public var gathersCoverage: Bool {
        guard let name = scheme, let s = model.loadSchemes().first(where: { $0.name == name }) else { return false }
        return s.document.child("TestAction")?["codeCoverageEnabled"] == "YES"
    }

    nonisolated static func coverage(request: BuildRequest, runner: TestRunner, summary: String) -> [CoverageItem] {
        if case .package(let dir) = request.container {
            return runner.packageCoverageJSON(packageDirectory: dir).map(CoverageModel.parseLLVMCovExport) ?? []
        }
        return FileManager.default.contents(atPath: summary).map(CoverageModel.parseSwiftCodebuildSummary) ?? []
    }

    public private(set) var reports: [BuildReport] = []

    public func recordReport(_ r: BuildReport) {
        reports.insert(r, at: 0)
        pruneReports()
        notify(.reports)
    }

    public var reportHistoryLimit = 20 {
        didSet { if reportHistoryLimit < reports.count { pruneReports(); notify(.reports) } }
    }

    func pruneReports() {
        if reports.count > max(1, reportHistoryLimit) { reports.removeLast(reports.count - max(1, reportHistoryLimit)) }
    }

    public var stopOnFirstError = true
    private var stoppedOnFirstError = false

    public internal(set) var debugClient: DAPClient?
    public internal(set) var simulatorRun: SimulatorRunState?
    public private(set) var consoleEntries: [ConsoleEntry] = []
    public private(set) var lastStopDescription: String?
    public private(set) var consoleHistory: [String] = []
    public var watchExpressions: [String] = [] { didSet { Task { await refreshWatches() } } }
    public private(set) var watchValues: [Variable] = []
    public private(set) var watchpoints: [Watchpoint] = []
    public var showRegisters = false { didSet { if oldValue != showRegisters { Task { await loadVariables(frameID: selectedFrameID) } } } }
    public var alwaysShowDisassembly = false { didSet { Task { await refreshDisassembly() } } }
    public private(set) var disassembly: [Instruction] = []
    public private(set) var disassemblyPCIndex: Int?
    public private(set) var variableContainers: [String: Int] = [:]
    public private(set) var stoppedThread: Int?
    public internal(set) var temporaryBreakpoint: (file: String, line: Int)?
    public internal(set) var variableBadges: [String: String] = [:]
    public internal(set) var isLoadingVariables = false
    var exitLinePrinted = false
    var killReported = false
    public internal(set) var breakpointIDs: [String: String] = [:]
    public internal(set) var breakpointHits: [String: Int] = [:]
    public internal(set) var stopAnnotation: (file: String, line: Int, text: String)?
    public internal(set) var stopCount = 0
    public var autoSelectedStop = 0
    public internal(set) var processGauges = ProcessGauges()
    var gaugeSampler: ProcessGaugeSampler?
    var gaugeTimer: Timer?
    public private(set) var frames: [StackFrame] = []
    public private(set) var variables: [Variable] = []
    public private(set) var threads: [DebugThread] = []
    public private(set) var selectedFrameID: Int?
    public var currentLocation: (file: String, line: Int)? {
        let f = frames.first { $0.id == selectedFrameID } ?? frames.first
        return f.flatMap { f in f.file.map { ($0, f.line) } }
    }

    private var currentBuild: BuildOperation?
    private var observers: [(Change) -> Void] = []

    public init(model: WorkspaceModel) {
        self.model = model
        scheme = model.schemeNames.first
        destination = model.destinations.first
    }

    public func observe(_ f: @escaping (Change) -> Void) { observers.append(f) }
    func notify(_ c: Change) { observers.forEach { $0(c) } }

    public var isBusy: Bool {
        switch activity { case .building, .running, .paused: true; default: false }
    }

    @discardableResult
    public func build(_ action: BuildRequest.Action = .build) async -> BuildResult {
        let request = model.buildRequest(scheme: scheme, destination: destination, action: action)
        let engine = self.engine
        return await performBuild(request, presentation: .init(action: action, subject: scheme ?? model.displayName), start: engine.start)
    }

    public enum BuildActivityText {
        public static let accepted = "Build"
        public static func accepted(_ action: BuildRequest.Action) -> String {
            switch action {
            case .test, .testWithoutBuilding: "Test"
            case .analyze: "Analyze"
            default: accepted
            }
        }
        public static let planning = "Building \u{2022} Planning deferred tasks"
        public static func progress(done: Int, total: Int) -> String { "Building \u{2022} \(done)/\(max(done, total))" }
        public static func isBuild(_ text: String) -> Bool {
            [accepted, "Test", "Analyze"].contains(text) || text.hasPrefix("Building ")
        }
    }

    public enum RunActivityText {
        public static func launching(_ product: String) -> String { "Launching \(product)" }
        public static let configuringDebugger = "Configuring Debugger Actions"
        public static func running(_ product: String, on device: String?) -> String { DebugPresentation.runningTitle(product, on: device) }
        public static func finished(_ product: String, on device: String?) -> String { DebugPresentation.finishedTitle(product, on: device) }
        public static let testAccepted = "Test"
        public static let testCompleted = "Test Completed"
        public static let testSucceeded = "Test Succeeded"
        public static let testFailed = "Test Failed"
    }

    struct BuildPresentation {
        var running: String
        var reportAction: String
        var title: String
        var succeeded: String, failed: String, cancelled: String
        var carriesOver: Bool

        init(running: String, reportAction: String, title: String, succeeded: String, failed: String, cancelled: String, carriesOver: Bool) {
            self.running = running
            self.reportAction = reportAction
            self.title = title
            self.succeeded = succeeded
            self.failed = failed
            self.cancelled = cancelled
            self.carriesOver = carriesOver
        }

        init(action: BuildRequest.Action, subject: String) {
            let verb = action == .clean ? "Cleaning" : (action == .test ? "Testing" : "Building")
            let noun = action == .clean ? "Clean" : (action == .test ? "Test" : "Build")
            let verbTitle = action == .clean ? "Clean" : (action == .test ? "Test" : "Build")
            let running = [.build, .test, .analyze].contains(action) ? BuildActivityText.accepted(action) : "\(verb) \(subject)"
            self.init(running: running, reportAction: verbTitle, title: "\(verbTitle) \(subject)",
                      succeeded: "\(noun) Succeeded", failed: "\(noun) Failed", cancelled: "Build Cancelled", carriesOver: action != .clean)
        }
    }

    @discardableResult
    func performBuild(_ request: BuildRequest, presentation p: BuildPresentation, keepsRunningApp: Bool = false,
                      start: (BuildRequest) -> BuildOperation) async -> BuildResult {
        if keepsRunningApp { currentBuild?.cancel() } else { stop() }
        issues = []
        issueEditState.editedSinceBuild = []
        resetBuildLog()
        notify(.issues)
        let started = Date()
        setActivity(.building(p.running))
        buildProgressState.seen = false
        let op = start(request)
        currentBuild = op
        stoppedOnFirstError = false
        var result = BuildResult(status: .cancelled, exitCode: -1, issues: [])
        for await event in op.events {
            handle(event)
            if case .finished(let r) = event { result = r }
        }
        currentBuild = nil
        if stoppedOnFirstError {
            if result.issues.isEmpty { result.issues = issues }
            result.status = .failed
        }
        let summary: String = switch result.status {
        case .succeeded: p.succeeded
        case .failed: p.failed
        case .cancelled: p.cancelled
        }
        issues = result.issues.filter { $0.severity != .note || $0.location != nil }
        notify(.issues)
        var report = BuildReport(title: p.title, date: Date(),
                                 succeeded: result.status == .succeeded, log: buildLog,
                                 errorCount: result.errorCount, warningCount: result.warningCount)
        report.context = reportContext(action: p.reportAction, started: started)
        report.context.issues = issues
        report.context.logTimes = buildLogTimes
        if p.carriesOver, let prev = reports.first(where: { $0.schemeName == report.schemeName && ($0.kind == .build || $0.kind == .clean) }),
           prev.kind == .build {
            report.context.carriedOver = BuildLogModel.carriedOver(from: prev, into: report)
        }
        reports.insert(report, at: 0)
        pruneReports()
        notify(.reports)
        setActivity(.finished(summary))
        return result
    }

    private func handle(_ event: BuildEvent) {
        switch event {
        case .output(let line): appendBuildLog(line)
        case .activity(let text):
            if !buildProgressState.seen { setActivity(.building(text)) }
        case .planning:
            buildProgressState.seen = true
            setActivity(.building(BuildActivityText.planning))
        case .progress(let done, let total):
            buildProgressState.seen = true
            setActivity(.building(BuildActivityText.progress(done: done, total: total)))
        case .issue(let d):
            issues.append(d)
            notify(.issues)
            if stopOnFirstError, d.severity == .error, !stoppedOnFirstError, let op = currentBuild {
                stoppedOnFirstError = true
                op.cancel()
            }
        case .finished: break
        }
    }

    final class BuildProgressState { var seen = false }
    let buildProgressState = BuildProgressState()

    public func noteToolActivity(_ a: Activity) { setActivity(a) }

    func setActivity(_ a: Activity) {
        activity = a
        notify(.activity)
    }

    public func run(program: String?, adapter: DAPTransport? = nil, building: Bool = true) async {
        if building {
            let result = await build(.build)
            guard result.status == .succeeded else { return }
        }
        guard let program else {
            appendConsole("SwiftCode: the scheme's executable could not be determined.\n")
            return
        }
        guard building || FileManager.default.fileExists(atPath: program) else {
            reportMissingProduct(program)
            return
        }
        await debug(program: program, adapter: adapter)
    }

    public struct LaunchOptions: Equatable, Sendable {
        public var arguments: [String] = []
        public var environment: [String: String] = [:]
        public var workingDirectory: String?
    }

    public var launchOptions: LaunchOptions {
        guard let name = scheme, let s = model.loadSchemes().first(where: { $0.name == name }) else { return LaunchOptions() }
        var o = LaunchOptions()
        o.arguments = s.launchArguments.filter(\.isEnabled).flatMap { RemoteSimulator.words($0.value) }
        for v in s.launchEnvironment where v.isEnabled && !v.key.isEmpty { o.environment[v.key] = v.value }
        if let d = s.customWorkingDirectory, !d.isEmpty { o.workingDirectory = d }
        s.diagnostics(for: "LaunchAction").applyLaunchEnvironment(&o.environment)
        return o
    }

    public func debug(program: String, adapter: DAPTransport? = nil) async {
        let transport: DAPTransport
        if let adapter { transport = adapter } else {
            guard let path = await Task.detached(operation: { LLDBDAP.locate() }).value else {
                appendConsole("SwiftCode: lldb-dap was not found.\n")
                return
            }
            transport = ProcessTransport(executable: path)
        }
        do {
            let client = try DAPClient(transport: transport)
            debugClient = client
            adapterInitialized = false
            beginDebugSession(product: URL(fileURLWithPath: program).lastPathComponent)
            setActivity(.running(runningActivityTitle))
            Task { [weak self] in
                for await e in client.events { await self?.handle(e) }
                self?.sessionEnded()
            }
            try await client.initialize()
            var o = launchOptions
            if o.environment["LLVM_PROFILE_FILE"] == nil {
                o.environment["LLVM_PROFILE_FILE"] = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-run-\(UUID().uuidString).profraw").path
            }
            try await client.launch(program: program, cwd: o.workingDirectory ?? URL(fileURLWithPath: program).deletingLastPathComponent().path,
                                    threadFormat: DebugThread.format, arguments: o.arguments, environment: o.environment)
        } catch {
            appendConsole("SwiftCode: \(error)\n")
            sessionEnded()
        }
    }

    var attachingSimulatorApp = false
    var stubForward: StubForward?

    public internal(set) var debuggedPID: Int?

    func handle(_ e: DAPEvent) async {
        guard let client = debugClient else { return }
        switch e.event {
        case "process":
            debuggedPID = e.body["systemProcessId"]?.int
            startGaugeSampling()
        case "initialized":
            adapterInitialized = true
            await syncBreakpoints()
            try? await client.configurationDone()
        case "output":
            if let text = e.body["output"]?.string {
                let category = e.body["category"]?.string ?? "console"
                appendConsole(text, kind: ["stdout", "stderr"].contains(category) ? .target : .debugger)
            }
        case "stopped":
            if temporaryBreakpoint != nil {
                temporaryBreakpoint = nil
                await syncBreakpoints()
            }
            if await runBreakpointActions(e.body) { return }
            var thread = e.body["threadId"]?.int
            if thread == nil { thread = try? await client.threads().first?.id }
            stoppedThread = thread
            await refreshStopState()
            lastStopDescription = e.body["description"]?.string ?? e.body["text"]?.string
            let reason = (lastStopDescription?.hasPrefix("watchpoint") == true ? lastStopDescription : nil) ?? e.body["reason"]?.string ?? "stopped"
            noteStop(e.body, threadID: thread, reason: reason)
            let plain = ["breakpoint", "step", "pause", "entry", "goto", "function breakpoint"].contains(reason)
            if !attachingSimulatorApp {
                setActivity(.paused(DebugPresentation.pausedTitle(runningProduct) + (plain ? "" : ": \(reason)")))
            }
        case "continued":
            clearStopState()
            setActivity(.running(runningActivityTitle))
        case "exited":
            let lead = console.isEmpty || console.hasSuffix("\n\n") ? "" : (console.hasSuffix("\n") ? "\n" : "\n\n")
            appendConsole(lead + "Program ended with exit code: \(e.body["exitCode"]?.int ?? 0)\n")
            exitLinePrinted = true
        case "terminated":
            client.close()
        default:
            break
        }
    }

    private func refreshStopState() async {
        guard let client = debugClient, let t = stoppedThread else { return }
        childrenCache = [:]
        threads = (try? await client.threads()) ?? []
        frames = (try? await client.stackTrace(threadID: t, levels: 50)) ?? []
        isLoadingVariables = true
        notify(.debugState)
        await loadVariables(frameID: frames.first?.id)
        await refreshWatches()
        await refreshDisassembly()
    }

    public func selectFrame(_ id: Int) async {
        guard frames.contains(where: { $0.id == id }) else { return }
        await loadVariables(frameID: id)
        await refreshWatches()
        await refreshDisassembly()
    }

    private func loadVariables(frameID: Int?) async {
        selectedFrameID = frameID
        childrenCache = [:]
        var vars: [Variable] = []
        variableContainers = [:]
        var badges: [String: String] = [:]
        let frameName = frames.first { $0.id == frameID }?.name
        if let client = debugClient, let frameID, let scopes = try? await client.scopes(frameID: frameID) {
            for s in scopes where showRegisters || (!s.expensive && !s.name.localizedCaseInsensitiveContains("register")) {
                let list = (try? await client.variables(reference: s.variablesReference)) ?? []
                for v in list where variableContainers[v.name] == nil {
                    variableContainers[v.name] = s.variablesReference
                    badges[v.name] = DebugPresentation.badge(name: v.name, scope: s.name, frameName: frameName)
                }
                vars += list
            }
        }
        variableBadges = badges
        isLoadingVariables = false
        variables = vars
        notify(.debugState)
    }

    public func children(of reference: Int) async -> [Variable] {
        guard reference != 0, let client = debugClient else { return [] }
        if let cached = childrenCache[reference] { return cached }
        let list = (try? await client.variables(reference: reference)) ?? []
        childrenCache[reference] = list
        return list
    }

    private var childrenCache: [Int: [Variable]] = [:]

    func clearStopState() {
        childrenCache = [:]
        stoppedThread = nil
        disassembly = []
        disassemblyPCIndex = nil
        frames = []
        variables = []
        threads = []
        selectedFrameID = nil
        notify(.debugState)
    }

    func sessionEnded() {
        debugClient = nil
        adapterInitialized = false
        temporaryBreakpoint = nil
        clearStopState()
        endDebugSession()
        if isBusy { setActivity(.finished(DebugPresentation.finishedTitle(runningProduct, on: runningDeviceName))) }
    }

    private var sentBreakpointFiles: Set<String> = []
    var adapterInitialized = false
    private var breakpointSync: Task<Void, Never>?

    func syncBreakpoints() async {
        let previous = breakpointSync
        let next = Task { await previous?.value; await sendBreakpoints() }
        breakpointSync = next
        await next.value
    }

    private func sendBreakpoints() async {
        guard let client = debugClient else { sentBreakpointFiles = []; return }
        guard adapterInitialized else { return }
        var current = breakpoints.effectiveBreakpoints
        if let t = temporaryBreakpoint, !(current[t.file] ?? []).contains(where: { $0.line == t.line && $0.column == nil }) {
            current[t.file, default: []].append(SourceBreakpoint(line: t.line))
        }
        for (file, list) in current {
            let result = (try? await client.setBreakpoints(file: file, breakpoints: list)) ?? []
            recordBreakpointIDs(file: file, sent: list, result: result)
        }
        for file in sentBreakpointFiles.subtracting(current.keys) {
            _ = try? await client.setBreakpoints(file: file, breakpoints: [])
        }
        sentBreakpointFiles = Set(current.keys)
        _ = try? await client.setFunctionBreakpoints(breakpoints.effectiveFunctionBreakpoints)
        let known = Set(client.exceptionFilters.map(\.id))
        _ = try? await client.setExceptionBreakpoints(filters: breakpoints.isActive ? breakpoints.exceptionFilters.filter { known.contains($0) } : [])
    }

    public func appendConsole(_ s: String) { appendConsole(s, kind: .debugger) }

    public func clearIssues() {
        issues = []
        packageIssues = []
        notify(.issues)
    }

    public func clearConsole() {
        console = ""
        consoleEntries = []
        notify(.console)
    }

    public func appendConsole(_ s: String, kind: ConsoleEntry.Kind) {
        console += s
        consoleEntries.append(ConsoleEntry(kind: kind, text: s, pid: kind == .target ? debuggedPID : nil))
        notify(.console)
    }

    @discardableResult
    public func evaluateInConsole(_ line: String) async -> String? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        consoleHistory.append(text)
        appendConsole("(lldb) \(text)\n", kind: .input)
        guard let client = debugClient else {
            appendConsole("error: no process is being debugged\n", kind: .debugger)
            return nil
        }
        do {
            let r = try await client.evaluateFull(text, frameID: selectedFrameID, context: "repl")
            let out = r.result.hasSuffix("\n") || r.result.isEmpty ? r.result : r.result + "\n"
            appendConsole(out, kind: .debugger)
            await loadVariables(frameID: selectedFrameID)
            return r.result
        } catch {
            let message = (error as? DAPError)?.message ?? "\(error)"
            appendConsole(message.hasPrefix("error:") ? message + "\n" : "error: \(message)\n", kind: .debugger)
            return nil
        }
    }

    public func consoleText(_ filter: ConsoleEntry.Filter, metadata: ConsoleMetadata = ConsoleMetadata()) -> String {
        Self.consoleText(consoleEntries.filter { filter.includes($0.kind) }, metadata: metadata)
    }

    nonisolated public static func consoleText(_ shown: [ConsoleEntry], metadata: ConsoleMetadata) -> String {
        guard metadata.enabled, metadata.type || metadata.timestamp || metadata.pidTID else { return shown.map(\.text).joined() }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return shown.map { e in
            var prefix = ""
            if metadata.timestamp { prefix += f.string(from: e.date) + " " }
            if metadata.pidTID, let pid = e.pid { prefix += "\(pid) " }
            if metadata.type { prefix += (e.kind == .target ? "[Target] " : e.kind == .input ? "[Input] " : "[Debugger] ") }
            let lines = e.text.split(separator: "\n", omittingEmptySubsequences: false)
            return lines.enumerated().map { i, l in (i == lines.count - 1 && l.isEmpty) ? "" : prefix + l }.joined(separator: "\n")
        }.joined()
    }

    func refreshWatches() async {
        guard let client = debugClient, stoppedThread != nil else { watchValues = []; return }
        var out: [Variable] = []
        for w in watchExpressions {
            if let r = try? await client.evaluateFull(w, frameID: selectedFrameID, context: "watch") {
                out.append(Variable(name: w, value: r.result, type: r.type, variablesReference: r.variablesReference))
            } else {
                out.append(Variable(name: w, value: "<unavailable>"))
            }
        }
        watchValues = out
        notify(.debugState)
    }

    @discardableResult
    public func setValue(_ value: String, of name: String, container: Int? = nil, expression: String? = nil) async -> String? {
        guard let client = debugClient, let ref = container ?? variableContainers[name] else { return nil }
        var r: String?
        do {
            r = try await client.setVariable(reference: ref, name: name, value: value)
        } catch {
            let message = (error as? DAPError)?.message ?? "\(error)"
            if let expression {
                do {
                    _ = try await client.evaluateFull("expression -- \(expression) = \(value)", frameID: selectedFrameID, context: "repl")
                    r = value
                } catch {
                    let m = (error as? DAPError)?.message ?? "\(error)"
                    appendConsole(m.hasPrefix("error:") ? m + "\n" : "error: \(m)\n", kind: .debugger)
                }
            } else {
                appendConsole("error: \(message)\n", kind: .debugger)
            }
        }
        await loadVariables(frameID: selectedFrameID)
        if !watchExpressions.isEmpty { await refreshWatches() }
        return r
    }

    @discardableResult
    public func printDescription(of name: String) async -> String? { await evaluateInConsole("po \(name)") }

    @discardableResult
    public func watch(_ name: String, container: Int? = nil, access: String = "write") async -> Watchpoint? {
        guard let client = debugClient, let ref = container ?? variableContainers[name],
              let info = try? await client.dataBreakpointInfo(reference: ref, name: name), let id = info.dataID else { return nil }
        let access = info.accessTypes.isEmpty || info.accessTypes.contains(access) ? access : info.accessTypes[0]
        var list = watchpoints.filter { $0.dataID != id }
        list.append(Watchpoint(name: name, dataID: id, description: info.description, accessType: access, verified: false))
        let result = (try? await client.setDataBreakpoints(list.map { ($0.dataID, $0.accessType) })) ?? []
        for i in list.indices where i < result.count { list[i].verified = result[i].verified }
        watchpoints = list
        notify(.breakpoints)
        return list.last
    }

    public func removeWatchpoint(_ w: Watchpoint) async {
        watchpoints.removeAll { $0.dataID == w.dataID }
        _ = try? await debugClient?.setDataBreakpoints(watchpoints.map { ($0.dataID, $0.accessType) })
        notify(.breakpoints)
    }

    public static func hasLocalSource(_ f: StackFrame) -> Bool {
        f.file.map { FileManager.default.fileExists(atPath: $0) } ?? false
    }

    func refreshDisassembly() async {
        let selected = frames.first(where: { $0.id == selectedFrameID }) ?? frames.first
        guard alwaysShowDisassembly || selected.map({ !Self.hasLocalSource($0) }) == true, let client = debugClient, stoppedThread != nil,
              let frame = selected, let pc = frame.instructionPointer else {
            disassembly = []
            disassemblyPCIndex = nil
            notify(.debugState)
            return
        }
        let list = ((try? await client.disassemble(memoryReference: pc, instructionOffset: -8, count: 40)) ?? []).filter {
            UInt64($0.address.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16) != nil
        }
        disassembly = list
        disassemblyPCIndex = list.firstIndex { Self.sameAddress($0.address, pc) }
        notify(.debugState)
    }

    static func sameAddress(_ a: String, _ b: String) -> Bool {
        func v(_ s: String) -> UInt64? { UInt64(s.lowercased().replacingOccurrences(of: "0x", with: ""), radix: 16) }
        return v(a) != nil && v(a) == v(b)
    }

    public func attach(to target: String, waitFor: Bool = false, adapter: DAPTransport? = nil) async {
        let transport: DAPTransport
        if let adapter { transport = adapter } else {
            guard let path = await Task.detached(operation: { LLDBDAP.locate() }).value else { appendConsole("SwiftCode: lldb-dap was not found.\n"); return }
            transport = ProcessTransport(executable: path)
        }
        do {
            let client = try DAPClient(transport: transport)
            debugClient = client
            adapterInitialized = false
            setActivity(.running("Attaching to \(target)"))
            Task { [weak self] in
                for await e in client.events { await self?.handle(e) }
                self?.sessionEnded()
            }
            try await client.initialize()
            let pid = Int(target)
            try await client.attach(pid: pid, program: pid == nil ? target : nil, waitFor: waitFor, threadFormat: DebugThread.format)
            beginDebugSession(product: pid == nil ? URL(fileURLWithPath: target).lastPathComponent : target)
            if pid != nil { debuggedPID = pid; startGaugeSampling() }
            setActivity(.running("Running \(target)"))
        } catch {
            appendConsole("SwiftCode: attach failed: \(error)\n")
            sessionEnded()
        }
    }

    public var threadsByQueue: [(queue: String, threads: [DebugThread])] {
        var out: [(String, [DebugThread])] = []
        for t in threads {
            let q = t.queue ?? "Threads"
            if let i = out.firstIndex(where: { $0.0 == q }) { out[i].1.append(t) } else { out.append((q, [t])) }
        }
        return out
    }

    public func continueOrPause() async {
        guard let c = debugClient else { return }
        if let t = stoppedThread { try? await c.continue(threadID: t); clearStopState(); setActivity(.running(runningActivityTitle)) }
        else if let t = try? await c.threads().first?.id { try? await c.pause(threadID: t) }
    }

    public func step(_ kind: String) async {
        guard let c = debugClient, let t = stoppedThread else { return }
        if alwaysShowDisassembly && kind != "out" {
            try? await c.stepInstruction(threadID: t, into: kind == "in")
            return
        }
        switch kind {
        case "in": try? await c.stepIn(threadID: t)
        case "out": try? await c.stepOut(threadID: t)
        default: try? await c.next(threadID: t)
        }
    }

    public func stop() {
        currentBuild?.cancel()
        if let c = debugClient {
            if !killReported {
                killReported = true
                appendConsole(DebugPresentation.killedLine + "\n", kind: .debugger)
            }
            Task { try? await c.disconnect(terminate: true); c.close() }
        }
    }
}

public struct ConsoleEntry: Equatable, Sendable {
    public enum Kind: Sendable { case debugger, target, input }
    public enum Filter: String, CaseIterable, Sendable {
        case all = "All Output", debugger = "Debugger Output", target = "Target Output"
        package func includes(_ k: Kind) -> Bool {
            switch self {
            case .all: true
            case .debugger: k != .target
            case .target: k == .target
            }
        }
    }
    public var kind: Kind
    public var text: String
    public var date = Date()
    public var pid: Int?
    public init(kind: Kind, text: String, date: Date = Date(), pid: Int? = nil) {
        self.kind = kind
        self.text = text
        self.date = date
        self.pid = pid
    }
}

public struct ConsoleMetadata: Equatable, Sendable {
    public static let columns = ["Type", "Timestamp", "Library", "PID:TID", "Subsystem", "Category"]
    public static let supportedColumns: Set<Int> = [0, 1, 3]
    public var pidTID: Bool { get { checked.contains(3) } set { set(3, newValue) } }
    public var enabled = true
    public var checked: Set<Int> = []
    public init() {}
    public var type: Bool { get { checked.contains(0) } set { set(0, newValue) } }
    public var timestamp: Bool { get { checked.contains(1) } set { set(1, newValue) } }
    public func isOn(_ i: Int) -> Bool { checked.contains(i) }
    public mutating func set(_ i: Int, _ on: Bool) {
        guard Self.columns.indices.contains(i) else { return }
        if on { checked.insert(i) } else { checked.remove(i) }
    }
}

public struct Watchpoint: Equatable, Sendable {
    public var name: String
    public var dataID: String
    public var description: String
    public var accessType: String
    public var verified: Bool
}
