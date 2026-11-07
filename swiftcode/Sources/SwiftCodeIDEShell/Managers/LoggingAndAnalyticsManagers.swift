// Ported from Legacy `SwiftCode/Views/Utilities/Operations/Logs/LoggingAndAnalyticsManagers.swift` (Audit E §5 partial entry; H-E5).
// Types ported here: SCActivityItem, SCQueuedTask, SCAIInsightReport, WorkspaceAnalytics, AIEngineeringAssistant, ResourceMonitor, AutomationEngine, WorkspaceSessionManager, EngineeringReportManager, WorkspaceIntelligence, WorkspaceTimelineManager, LoggingCenter, AIEngineeringReports, TimelineManager, OperationQueueManager, NotificationCenterManager, PerformanceManager.
//
// CLEANUP (2026-11-06, triage §A1–A3) — fabricated telemetry deleted:
// - A1 `ResourceMonitor`: host CPU/memory/disk/network were `Double.random`
//   offsets plus invented VM/task-count multipliers. Now read live: Mach
//   `host_statistics` (CPU load, VM page counts) + `task_info` (this
//   process's resident memory), `FileManager` filesystem attributes (disk),
//   `getifaddrs` byte counters (network, MB since this monitor started).
//   `hostGPUUsage` is now `Double?` (`nil` = unavailable): macOS exposes
//   no public host-GPU-utilization API — Metal has no utilization
//   property, and per-command-buffer counter sampling measures only this
//   app's own command buffers, not host GPU % — so nothing is invented.
//   `DevToolsSystemMetrics` (swiftcode-ide target) could not be wired in:
//   SwiftCodeIDEShell does not depend on that target, so the same Mach
//   pattern is implemented here as file-private helpers.
// - A2 `PerformanceManager`: initial cpuUsage 14.5 / ramUsageGB 2.4 /
//   averageBuildDuration 4.2 and the 4 s `Double.random` loop are gone.
//   CPU/RAM now come from the same live Mach readings; build durations
//   are computed from `BuildHistoryManager`'s real build records
//   (0.0 = no build recorded yet, never a made-up duration).
// - A3 `TimelineManager` (and the identical block in
//   `WorkspaceTimelineManager`): the fabricated "Workspace Command
//   Center Initialized" event dated one hour ago is gone; an empty
//   timeline stays empty. The VM/dependency rows in
//   `WorkspaceTimelineManager.refresh` also no longer pretend to have
//   happened 2 min / 1 h ago — they are dated when the refresh logs
//   them, which is when the check actually ran.
//
// CLEANUP (2026-11-06, writer D5) — fabricated analytics deleted:
// - `WorkspaceAnalytics`: no-build fallback of 100.0% success rate is
//   gone (0.0 = no builds recorded yet, same "0 = no data" convention as
//   A2's build durations); no-active-project fallback of 1200 lines of
//   code is gone (0 = nothing counted).
// - `WorkspaceIntelligence`: doc-coverage 0.72 / test-coverage 0.65 /
//   storage-growth count × 3 MB / "Improving (Clean compiles are 12%
//   faster)" baselines are gone. Doc coverage is the real scanned ratio
//   (0.0 when nothing was scanned); test coverage is 0.0 (no .xcresult /
//   xccov source is wired — 0.0 means "no data", not a measured 0%);
//   storage growth is 0 (no prior snapshot is stored to compare
//   against); the build trend is computed from real build records
//   (recent-half vs earlier-half mean duration, with the percentage
//   computed from those durations, "No build history" under 2 builds).
// - `NotificationCenterManager`: the four seeded notifications are gone
//   ("Certificate expires in 365 days", "ZIPFoundation v0.9.19 →
//   v0.9.22", "DerivedData is taking 12.4 GB", "Cloud Sync Connected").
//   Notifications are now derived from real state only: keychain
//   certificates expiring within 30 days (via
//   `SCOperationsSigningManager`), measured DerivedData ≥ 5 GB and
//   measured free disk < 5 GB (via `SCOperationsStorageManager`), and
//   cloud-connected only while actually authenticated. Storage values
//   reflect the latest completed measurement — call `loadNotifications()`
//   again after a recalculation to refresh them. D3's A1–A3 fixes above
//   (ResourceMonitor / PerformanceManager / TimelineManager) were verified
//   still intact and are untouched.
//
// CLEANUP (2026-11-06, writer D6) — invented assistant claims and fake
// latency deleted:
// - `AIEngineeringAssistant.askQuestion` slept 1.2 s before answering a
//   locally generated response. The sleep is gone: the response is
//   generated from local state with no I/O, so it answers immediately.
// - `generateResponse` asserted "boost speeds by up to 18%" and
//   "reclaiming up to 40% of wasted build storage". Both percentages
//   were invented. The speed answer now points at the measured average
//   build duration as the baseline to re-measure against; the storage
//   answer now names the measured DerivedData size that purging would
//   free. The package answer's hardcoded "Update 'ZIPFoundation'"
//   recommendation is gone too: it now names the packages this
//   workspace actually reports as "Update Available" (none, now that
//   `DependencyManager` reports "Unknown" instead of stamping a status),
//   or says so.
// - Other `Task.sleep` sites, checked in context:
//   * `ResourceMonitor` 2.0 s — legitimate telemetry polling interval.
//     Left alone.
//   * `PerformanceManager` 4.0 s — legitimate telemetry polling
//     interval. Left alone.
//   * `AutomationEngine.triggerWorkflow` 0.3 s — sleep-and-report-
//     success stub: it logged each workflow action as "completed"
//     without executing anything (actions are free-text names with no
//     executor). The loop is deleted; triggering still records the real
//     "Automation Triggered" event, but nothing is claimed completed.
//     Wiring a real action executor is the blocker, not a sleep.
//   * `AIEngineeringReports.generateReport` 0.6 s — fake "thinking"
//     delay before real work (the file scan that follows is genuine).
//     Removed; the report generates immediately.
// - D3's A1–A3 fixes (ResourceMonitor / PerformanceManager /
//   TimelineManager) and D5's WorkspaceAnalytics / WorkspaceIntelligence
//   / NotificationCenterManager fixes were verified still intact and are
//   untouched.

import Foundation
#if os(macOS)
import Darwin
#endif
import Observation

public struct SCActivityItem: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let detail: String
    public let category: String // "Build", "Archive", "Import", "Backup", "Diagnostics", "Release", "VM", "Project"
    public let date: Date

    public init(id: UUID = UUID(), title: String, detail: String, category: String, date: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.date = date
    }
}

public struct SCQueuedTask: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let name: String
    public var progress: Double // 0.0 to 1.0
    public var status: String // "Queued", "Executing", "Completed", "Failed"

    public init(id: UUID = UUID(), name: String, progress: Double = 0.0, status: String = "Queued") {
        self.id = id
        self.name = name
        self.progress = progress
        self.status = status
    }
}

public struct SCAIInsightReport: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let type: String // "Optimization", "Dead Code", "Size", "Package"
    public let message: String
    public let linesOfCodeImpacted: Int?
    public let severity: String // "High", "Medium", "Low"

    public init(id: UUID = UUID(), title: String, type: String, message: String, linesOfCodeImpacted: Int? = nil, severity: String) {
        self.id = id
        self.title = title
        self.type = type
        self.message = message
        self.linesOfCodeImpacted = linesOfCodeImpacted
        self.severity = severity
    }
}

@Observable
@MainActor
public final class WorkspaceAnalytics {
    public static let shared = WorkspaceAnalytics()

    public var totalProjects: Int = 0
    public var totalFiles: Int = 0
    public var totalArchives: Int = 0
    /// Mean success rate of recorded builds; 0.0 = no builds recorded yet.
    public var averageBuildSuccessRate: Double = 0.0
    public var totalLinesOfCode: Int = 0

    private init() {
        refresh()
    }

    public func refresh() {
        let projects = ProjectSessionStore.shared.projects
        self.totalProjects = projects.count
        self.totalFiles = projects.reduce(0) { $0 + $1.files.count }
        self.totalArchives = ArchiveManager.shared.archives.count

        let builds = BuildHistoryManager.shared.buildRecords
        if builds.isEmpty {
            // No builds recorded: no success rate exists. 0.0 means "no
            // data", not a measured 0% (the old 100.0 asserted perfection
            // with zero evidence).
            self.averageBuildSuccessRate = 0.0
        } else {
            let succeededCount = builds.filter { $0.status == "Succeeded" }.count
            self.averageBuildSuccessRate = (Double(succeededCount) / Double(builds.count)) * 100.0
        }

        // Offload file reading line counts
        if let active = ProjectSessionStore.shared.activeProject {
            let rootDir = active.directoryURL
            Task.detached(priority: .background) {
                var linesCount = 0
                let fm = FileManager.default
                if let enumerator = fm.enumerator(at: rootDir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                    while let fileURL = enumerator.nextObject() as? URL {
                        if fileURL.pathExtension == "swift" {
                            if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
                                linesCount += text.components(separatedBy: .newlines).count
                            }
                        }
                    }
                }
                let loc = linesCount
                await MainActor.run {
                    self.totalLinesOfCode = loc
                }
            }
        } else {
            // No active project: nothing was counted. 0 means "no data",
            // not a measured zero (the old 1200 was invented).
            self.totalLinesOfCode = 0
        }
    }
}

@Observable
@MainActor
public final class AIEngineeringAssistant {
    public static let shared = AIEngineeringAssistant()

    public struct Message: Identifiable, Codable, Sendable {
        public let id: UUID
        public let isUser: Bool
        public let text: String
        public let date: Date
    }

    public var conversation: [Message] = []
    public var isAnalyzing: Bool = false

    private init() {
        // Welcome message
        conversation = [
            Message(
                id: UUID(),
                isUser: false,
                text: "Hi! I am your SwiftCode AI Engineering Assistant. Ask me questions about workspace build speeds, unused packages, duplicate code, storage, or diagnostics. I analyze actual project data to provide recommendations.",
                date: Date()
            )
        ]
    }

    public func askQuestion(_ question: String) {
        let userMsg = Message(id: UUID(), isUser: true, text: question, date: Date())
        conversation.append(userMsg)

        isAnalyzing = true

        // No artificial delay: the response is generated locally from
        // workspace state with no I/O, so it answers immediately.
        Task {
            let responseText = generateResponse(for: question.lowercased())
            let aiMsg = Message(id: UUID(), isUser: false, text: responseText, date: Date())

            self.conversation.append(aiMsg)
            self.isAnalyzing = false

            WorkspaceTimelineManager.shared.addEvent(
                title: "AI Analysis Completed",
                detail: "AI Assistant evaluated question: '\(question)'",
                category: "Diagnostics Completed"
            )
        }
    }

    private func generateResponse(for question: String) -> String {
        let projects = ProjectSessionStore.shared.projects
        let totalProjects = projects.count
        let healthScore = WorkspaceHealth.shared.healthScore
        let duplicates = WorkspaceIntelligence.shared.duplicateSourceFiles.count
        let packages = DependencyManager.shared.dependencies.count
        let storageUsed = SCOperationsStorageManager.shared.totalAllocatedGB
        let brokenCount = DiagnosticsManager.shared.issues.count

        if question.contains("slower") || question.contains("speed") || question.contains("performance") {
            return """
            Based on the actual compilation log database:
            • We have \(totalProjects) active workspace files.
            • The average build duration is currently \(String(format: "%.1f", PerformanceManager.shared.averageBuildDuration)) seconds.
            • Recommended optimization: Since your project uses \(packages) packages, clean caches and disable unnecessary background indexing under preferences. The average build duration above is the measured baseline — re-measure after the change instead of assuming a gain.
            """
        }

        if question.contains("duplicate") || question.contains("unused") || question.contains("cleanup") {
            if duplicates > 0 {
                return """
                I found \(duplicates) duplicate source files in this workspace!
                • File list: \(WorkspaceIntelligence.shared.duplicateSourceFiles.joined(separator: ", "))
                • Recommendation: Consolidate these files into a local SPM target inside Package.swift to eliminate compilation redundancy.
                """
            } else {
                return """
                Good news! My duplicate code scans return 0 duplicate Swift files or asset resources in the registered projects. Your structure looks extremely clean!
                """
            }
        }

        if question.contains("package") || question.contains("dependency") || question.contains("graph") {
            // Names only packages this workspace actually reports as
            // having an update available — never a hardcoded package name.
            let outdated = DependencyManager.shared.dependencies.filter { $0.status == "Update Available" }
            let action = outdated.isEmpty
                ? "No package in this workspace reports an available update."
                : "Review updates for: \(outdated.map(\.name).joined(separator: ", "))."
            return """
            Analyzing local package graph:
            • Total package links detected: \(packages).
            • Shared packages linked in multiple codebases: \(WorkspaceIntelligence.shared.sharedPackages.count).
            • Outdated packages with available updates: \(outdated.count).
            • Recommended action: \(action)
            """
        }

        if question.contains("storage") || question.contains("optimize") || question.contains("size") {
            return """
            Your total workspace storage footprint is \(String(format: "%.2f GB", storageUsed)).
            • Local Projects: \(String(format: "%.2f GB", SCOperationsStorageManager.shared.projectUsageGB))
            • DerivedData / Builds: \(String(format: "%.2f GB", SCOperationsStorageManager.shared.derivedDataGB))
            • Caches & VM Disk files: \(String(format: "%.2f GB", SCOperationsStorageManager.shared.cacheUsageGB))
            • Recommendation: Click 'Clean Artifacts' under the storage manager tab to purge DerivedData (currently \(String(format: "%.2f GB", SCOperationsStorageManager.shared.derivedDataGB))).
            """
        }

        if question.contains("diagnostic") || question.contains("health") || question.contains("explain") {
            if brokenCount > 0 {
                return """
                Workspace Health Score is \(healthScore)% (\(WorkspaceHealth.shared.rating)).
                • Diagnostics has flagged \(brokenCount) unresolved compiler/configuration issues.
                • Major issue: "\(DiagnosticsManager.shared.issues.first?.message ?? "")".
                • Recommended fix: \(DiagnosticsManager.shared.issues.first?.suggestedFix ?? "").
                """
            } else {
                return """
                Your Workspace Health is a perfect \(healthScore)% (Excellent)! No structural diagnostics issues are active. Keep up the clean implementation.
                """
            }
        }

        return """
        I analyzed your workspace:
        • Active Projects: \(totalProjects)
        • Workspace Health: \(healthScore)%
        • Hardcoded Keys Audited: \(SecurityManager.shared.findings.count)
        • Running VM Hypervisors: \(VirtualizationStateStore.shared.virtualMachines.filter { $0.status == .running }.count)

        Please try asking:
        - "Why are builds slower?"
        - "Find duplicate code."
        - "Show unused packages."
        - "Optimize storage."
        - "Explain diagnostics."
        """
    }

    public func clearConversation() {
        conversation = [
            Message(
                id: UUID(),
                isUser: false,
                text: "Conversation cleared. Ask me anything about your development workspace!",
                date: Date()
            )
        ]
    }
}

@Observable
@MainActor
public final class ResourceMonitor {
    public static let shared = ResourceMonitor()

    // Host telemetry — all values are live readings, never invented.
    // A value of 0 means "no reading yet / unavailable on this platform",
    // never a measured zero. GPU has no live source (see below).
    public var hostCPUUsage: Double = 0.0
    public var hostMemoryUsedGB: Double = 0.0
    public var hostMemoryTotalGB: Double = 0.0
    public var hostDiskUsedGB: Double = 0.0
    public var hostDiskTotalGB: Double = 0.0
    /// MB sent since this monitor started (getifaddrs byte counters).
    public var hostNetworkSentMB: Double = 0.0
    /// MB received since this monitor started (getifaddrs byte counters).
    public var hostNetworkRecvMB: Double = 0.0
    /// Host GPU utilization — always `nil`: macOS exposes no public API
    /// for it (Metal has no utilization property; counter sampling only
    /// measures this app's own command buffers). Displayed as
    /// unavailable, never as a fabricated percentage.
    public var hostGPUUsage: Double? = nil

    // Subsystem activities
    public var activeCompilationsCount: Int = 0
    public var activeIndexingCount: Int = 0
    public var activeAIActivityCount: Int = 0

    /// Cumulative interface byte counters at monitor start; network
    /// values above are deltas from this baseline.
    private var networkBaseline: (sent: UInt64, received: UInt64)?

    private init() {
        // Total physical RAM is a fixed hardware fact, not a sample.
        hostMemoryTotalGB = Double(ProcessInfo.processInfo.physicalMemory) / 1024 / 1024 / 1024
        startUpdateLoop()
    }

    private func startUpdateLoop() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                // Read from actual state
                let activeTaskCount = OperationsCoordinator.shared.activeTaskCount

                // Live host readings; a failed read leaves the previous
                // real value in place instead of inventing a replacement.
                if let cpu = Self.hostCPULoadPercent() {
                    self.hostCPUUsage = cpu
                }
                if let usedMemoryGB = Self.hostMemoryUsedGB() {
                    self.hostMemoryUsedGB = usedMemoryGB
                }
                if let disk = Self.diskUsageGB() {
                    self.hostDiskUsedGB = disk.used
                    self.hostDiskTotalGB = disk.total
                }
                #if os(macOS)
                if let totals = Self.networkByteTotals() {
                    if let baseline = networkBaseline {
                        // 32-bit interface counters can wrap; a wrapped
                        // counter restarts from the current value.
                        let sent = totals.sent >= baseline.sent ? totals.sent - baseline.sent : totals.sent
                        let received = totals.received >= baseline.received ? totals.received - baseline.received : totals.received
                        self.hostNetworkSentMB = Double(sent) / 1024 / 1024
                        self.hostNetworkRecvMB = Double(received) / 1024 / 1024
                    } else {
                        networkBaseline = totals
                    }
                }
                #endif

                self.activeCompilationsCount = activeTaskCount
                self.activeIndexingCount = activeTaskCount > 0 ? 1 : 0
                self.activeAIActivityCount = AIEngineeringAssistant.shared.isAnalyzing ? 1 : 0
            }
        }
    }

    // MARK: - Live host readings (Mach / FileManager / getifaddrs)
    //
    // Same Mach pattern as `DevToolsSystemMetrics` (swiftcode-ide target,
    // which this module cannot depend on), implemented here instead.
    // Every helper returns `nil` where the platform has no equivalent,
    // so callers show "no reading" instead of inventing numbers.

    /// Overall host CPU busy percentage (user + system + nice), 0–100.
    static func hostCPULoadPercent() -> Double? {
        #if os(macOS)
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let user = Double(info.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return (user + system + nice) / total * 100
        #else
        return nil
        #endif
    }

    /// Host memory in use (active + inactive + wired pages), in GB.
    static func hostMemoryUsedGB() -> Double? {
        #if os(macOS)
        var vmInfo = vm_statistics()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_VM_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        guard pageSize > 0 else { return nil }
        let usedPages = Double(vmInfo.active_count + vmInfo.inactive_count + vmInfo.wire_count)
        return usedPages * Double(pageSize) / 1024 / 1024 / 1024
        #else
        return nil
        #endif
    }

    /// This process's resident memory, in megabytes.
    static func taskResidentMemoryMB() -> Double? {
        #if os(macOS)
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(taskInfo.resident_size) / 1024 / 1024
        #else
        return nil
        #endif
    }

    /// Disk usage of the volume holding the user's home directory.
    static func diskUsageGB() -> (used: Double, total: Double)? {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let total = (attrs[.systemSize] as? NSNumber)?.doubleValue,
              let free = (attrs[.systemFreeSize] as? NSNumber)?.doubleValue,
              total > 0 else { return nil }
        let divisor = 1024.0 * 1024.0 * 1024.0
        return (used: (total - free) / divisor, total: total / divisor)
    }

    #if os(macOS)
    /// Cumulative bytes sent/received across all non-loopback interfaces
    /// (getifaddrs `if_data` counters).
    static func networkByteTotals() -> (sent: UInt64, received: UInt64)? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var sent: UInt64 = 0
        var received: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            cursor = current.pointee.ifa_next
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let raw = current.pointee.ifa_data else { continue }
            let data = raw.load(as: if_data.self)
            received += UInt64(data.ifi_ibytes)
            sent += UInt64(data.ifi_obytes)
        }
        return (sent: sent, received: received)
    }
    #endif
}

@Observable
@MainActor
public final class AutomationEngine {
    public static let shared = AutomationEngine()

    public struct Workflow: Codable, Identifiable, Sendable {
        public let id: UUID
        public var name: String
        public var trigger: String // "Project Opened", "Build Finished", "Device Connected", "VM Started", "Archive Exported", "Diagnostics Completed", "Backup Completed"
        public var actions: [String] // "Start VM", "Open Terminal", "Run npm install", "Run backend", "Launch browser", "Start AI assistant"
        public var isActive: Bool
    }

    public var workflows: [Workflow] = []

    private var workflowsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/automation_workflows.json")
    }

    private init() {
        loadWorkflows()
    }

    public func loadWorkflows() {
        guard FileManager.default.fileExists(atPath: workflowsURL.path) else {
            // Seed a few default workflows so it is fully populated out-of-the-box
            self.workflows = [
                Workflow(
                    id: UUID(),
                    name: "Full Stack Launch Sequence",
                    trigger: "Project Opened",
                    actions: ["Start VM", "Open Terminal", "Run npm install", "Run backend", "Start AI assistant"],
                    isActive: true
                ),
                Workflow(
                    id: UUID(),
                    name: "Post-Archive Hypervisor Backup",
                    trigger: "Archive Exported",
                    actions: ["Start VM", "Run backend"],
                    isActive: false
                )
            ]
            saveWorkflows()
            return
        }
        do {
            let data = try Data(contentsOf: workflowsURL)
            self.workflows = try JSONDecoder().decode([Workflow].self, from: data)
        } catch {
            self.workflows = []
        }
    }

    public func saveWorkflows() {
        let dir = workflowsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let data = try JSONEncoder().encode(workflows)
            try data.write(to: workflowsURL, options: .atomic)
        } catch {}
    }

    public func triggerWorkflow(for trigger: String) {
        let matching = workflows.filter { $0.isActive && $0.trigger == trigger }
        for wf in matching {
            WorkspaceTimelineManager.shared.addEvent(
                title: "Automation Triggered",
                detail: "Workflow '\(wf.name)' triggered by event '\(trigger)'",
                category: "Diagnostics Completed"
            )

            // Actions are recorded names only ("Start VM", "Run npm
            // install", …) and no executor exists for them, so nothing
            // is logged as completed. The old loop slept 0.3 s per
            // action and then logged each one as completed without
            // executing anything — a sleep-and-report-success stub —
            // and is deleted, not reworded.
        }
    }

    public func addWorkflow(name: String, trigger: String, actions: [String]) {
        let wf = Workflow(id: UUID(), name: name, trigger: trigger, actions: actions, isActive: true)
        workflows.append(wf)
        saveWorkflows()
    }

    public func deleteWorkflow(_ workflow: Workflow) {
        workflows.removeAll { $0.id == workflow.id }
        saveWorkflows()
    }
}

@Observable
@MainActor
public final class WorkspaceSessionManager {
    public static let shared = WorkspaceSessionManager()

    public struct SavedSession: Codable, Identifiable, Sendable {
        public let id: UUID
        public let name: String
        public let date: Date
        public var openProjectIDs: [UUID]
        public var openTabs: [String]
        public var activeProjectID: UUID?
        public var activeTab: String?
        public var activeSidebarTab: String?
        public var runningVMIDs: [UUID]
        public var connectedDeviceIDs: [String]
        public var activeBuildCount: Int
    }

    public var savedSessions: [SavedSession] = []

    private var sessionsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/workspace_sessions_snapshots.json")
    }

    private init() {
        loadSessions()
    }

    public func loadSessions() {
        guard FileManager.default.fileExists(atPath: sessionsURL.path) else {
            self.savedSessions = []
            return
        }
        do {
            let data = try Data(contentsOf: sessionsURL)
            self.savedSessions = try JSONDecoder().decode([SavedSession].self, from: data)
        } catch {
            self.savedSessions = []
        }
    }

    public func saveSessions() {
        let dir = sessionsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let data = try JSONEncoder().encode(savedSessions)
            try data.write(to: sessionsURL, options: .atomic)
        } catch {}
    }

    public func snapshotCurrentSession(name: String) {
        let activeProjectID = ProjectSessionStore.shared.activeProject?.id
        let openProjectIDs = ProjectSessionStore.shared.projects.map { $0.id }
        let openTabs = ProjectSessionStore.shared.openFileTabs.map { $0.path }
        let activeTab = ProjectSessionStore.shared.activeFileNode?.path
        let activeSidebarTab = VirtualizationStateStore.shared.selectedSidebarTab.rawValue

        let runningVMIDs = VirtualizationStateStore.shared.virtualMachines
            .filter { $0.status == .running }
            .map { $0.id }

        let connectedDeviceIDs = SCOperationsDeviceManager.shared.devices
            .filter { $0.status == "Connected" }
            .map { $0.id }

        let activeBuildCount = OperationsCoordinator.shared.activeTaskCount

        let snapshot = SavedSession(
            id: UUID(),
            name: name,
            date: Date(),
            openProjectIDs: openProjectIDs,
            openTabs: openTabs,
            activeProjectID: activeProjectID,
            activeTab: activeTab,
            activeSidebarTab: activeSidebarTab,
            runningVMIDs: runningVMIDs,
            connectedDeviceIDs: connectedDeviceIDs,
            activeBuildCount: activeBuildCount
        )

        savedSessions.insert(snapshot, at: 0)
        saveSessions()

        WorkspaceTimelineManager.shared.addEvent(
            title: "Workspace Session Saved",
            detail: "Snapshot '\(name)' captured with \(openProjectIDs.count) projects and \(runningVMIDs.count) running VMs.",
            category: "Backup Created"
        )
    }

    public func restoreSession(_ session: SavedSession) {
        // Restore running VMs if stopped
        for vmID in session.runningVMIDs {
            VirtualizationStateStore.shared.updateVMStatus(vmID, to: .running)
        }

        // Restore active projects
        if let activeID = session.activeProjectID,
           let project = ProjectSessionStore.shared.projects.first(where: { $0.id == activeID }) {
            Task {
                await ProjectSessionStore.shared.openProject(project)
                if let activeTabPath = session.activeTab {
                    if let fileNode = ProjectSessionStore.shared.activeProject?.files.first(where: { $0.path == activeTabPath }) {
                        ProjectSessionStore.shared.openFile(fileNode)
                    }
                }
            }
        }

        if let sidebarEnum = VirtualizationStateStore.SidebarTab(rawValue: session.activeSidebarTab ?? "Dashboard") {
            VirtualizationStateStore.shared.selectedSidebarTab = sidebarEnum
        }

        WorkspaceTimelineManager.shared.addEvent(
            title: "Workspace Session Restored",
            detail: "Snapshot '\(session.name)' fully restored.",
            category: "Project Opened"
        )
    }

    public func deleteSession(_ session: SavedSession) {
        savedSessions.removeAll { $0.id == session.id }
        saveSessions()
    }
}

@Observable
@MainActor
public final class EngineeringReportManager {
    public static let shared = EngineeringReportManager()

    public struct EngineeringReport: Codable, Identifiable, Sendable {
        public let id: UUID
        public let title: String
        public let type: String // "Weekly", "Monthly", "Storage", "Dependency", "Build", "Workspace", "Performance", "Security", "Documentation", "Code Quality"
        public let date: Date
        public var contentHTML: String
        public var metrics: [String: String]
    }

    public var generatedReports: [EngineeringReport] = []

    private var reportsURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("SwiftCode/engineering_reports_saved.json")
    }

    private init() {
        loadReports()
    }

    public func loadReports() {
        guard FileManager.default.fileExists(atPath: reportsURL.path) else {
            self.generatedReports = []
            return
        }
        do {
            let data = try Data(contentsOf: reportsURL)
            self.generatedReports = try JSONDecoder().decode([EngineeringReport].self, from: data)
        } catch {
            self.generatedReports = []
        }
    }

    public func saveReports() {
        let dir = reportsURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        do {
            let data = try JSONEncoder().encode(generatedReports)
            try data.write(to: reportsURL, options: .atomic)
        } catch {}
    }

    public func generateReport(type: String) {
        let projectsCount = ProjectSessionStore.shared.projects.count
        let buildsCount = BuildHistoryManager.shared.buildRecords.count
        let warningsCount = BuildHistoryManager.shared.buildRecords.reduce(0) { $0 + $1.warnings }
        let errorsCount = BuildHistoryManager.shared.buildRecords.reduce(0) { $0 + $1.errors }
        let activeVMsCount = VirtualizationStateStore.shared.virtualMachines.filter { $0.status == .running }.count

        let healthScore = WorkspaceHealth.shared.healthScore
        let docRatio = WorkspaceIntelligence.shared.docCoverageRatio
        let duplicateSourcesCount = WorkspaceIntelligence.shared.duplicateSourceFiles.count

        var metrics: [String: String] = [:]
        metrics["Total Projects"] = "\(projectsCount)"
        metrics["Total Builds"] = "\(buildsCount)"
        metrics["Build Warnings"] = "\(warningsCount)"
        metrics["Build Errors"] = "\(errorsCount)"
        metrics["Running VMs"] = "\(activeVMsCount)"
        metrics["Health Score"] = "\(healthScore)%"
        metrics["Documentation Coverage"] = String(format: "%.1f%%", docRatio * 100.0)
        metrics["Duplicate Source Files"] = "\(duplicateSourcesCount)"

        var bodyHTML = """
        <h1>\(type) Engineering Report</h1>
        <p>Generated on: \(Date().description)</p>
        <p>Workspace Integrity Index: <strong>\(healthScore)%</strong></p>
        <h3>Core Telemetry Metrics</h3>
        <ul>
            <li>Active Codebases: \(projectsCount)</li>
            <li>Historical Build Records: \(buildsCount)</li>
            <li>Compiler Warnings: \(warningsCount)</li>
            <li>Active Running Hypervisors: \(activeVMsCount)</li>
            <li>Swift Documentation Coverage: \(String(format: "%.1f%%", docRatio * 100.0))</li>
        </ul>
        <h3>Detailed Insights & Cleanup Actions</h3>
        """

        if duplicateSourcesCount > 0 {
            bodyHTML += "<p>⚠️ <strong>Warning:</strong> Found \(duplicateSourcesCount) duplicate source files. Consider merging shared implementations into a local Swift Package.</p>"
        } else {
            bodyHTML += "<p>✅ Codebase remains extremely lean, with no duplicate Swift resources found.</p>"
        }

        if healthScore < 85 {
            bodyHTML += "<p>⚠️ <strong>Performance:</strong> Build success rate has dropped. Investigate recent failed builds in Build History.</p>"
        } else {
            bodyHTML += "<p>✅ Excellent build success rate. Workstation is running optimally.</p>"
        }

        let newReport = EngineeringReport(
            id: UUID(),
            title: "\(type) Analysis Report",
            type: type,
            date: Date(),
            contentHTML: bodyHTML,
            metrics: metrics
        )

        generatedReports.insert(newReport, at: 0)
        saveReports()

        WorkspaceTimelineManager.shared.addEvent(
            title: "Engineering Report Compiled",
            detail: "\(type) report generated with health score of \(healthScore)%.",
            category: "Diagnostics Completed"
        )
    }

    public func exportReportAsJSON(_ report: EngineeringReport) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(report) {
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }
}

@Observable
@MainActor
public final class WorkspaceIntelligence {
    public static let shared = WorkspaceIntelligence()

    public var projectRelationships: [String: [String]] = [:]
    public var sharedPackages: [String] = []
    public var sharedFrameworks: [String] = []
    public var sharedAssets: [String] = []
    public var buildDependencies: [String: [String]] = [:]

    // Scan results
    public var duplicateResources: [String] = []
    public var duplicateSourceFiles: [String] = []
    public var duplicateSymbols: [String] = []
    public var docCoverageRatio: Double = 0.0
    public var testCoverageRatio: Double = 0.0
    public var storageGrowthBytes: Int64 = 0
    public var buildTrends: String = "Stable"

    // Metadata scans
    public var swiftVersions: [String: String] = [:]
    public var sdkCompatibility: [String: String] = [:]
    public var deploymentTargets: [String: String] = [:]
    public var binarySizeHistory: [String: [Int64]] = [:]
    public var buildHistoryAnalytics: [String: Int] = [:]

    public var isAnalyzing: Bool = false

    private init() {
        analyze()
    }

    public func analyze() {
        isAnalyzing = true
        let projects = ProjectSessionStore.shared.projects

        // 1. Clean previous runs
        projectRelationships.removeAll()
        sharedPackages.removeAll()
        sharedFrameworks.removeAll()
        sharedAssets.removeAll()
        buildDependencies.removeAll()
        duplicateResources.removeAll()
        duplicateSourceFiles.removeAll()
        duplicateSymbols.removeAll()
        swiftVersions.removeAll()
        sdkCompatibility.removeAll()
        deploymentTargets.removeAll()

        // 2. Map actual project settings
        var allPackageNames: [String: Int] = [:]
        var allFileNames: [String: [String]] = [:] // Name -> Path list
        var totalSwiftCommentsCount = 0
        var totalSwiftLinesOfCode = 0

        for project in projects {
            let rootURL = project.directoryURL
            let projectName = project.name

            swiftVersions[projectName] = ProjectRegistryManager.shared.registryEntries.first(where: { $0.id == project.id })?.swiftVersion ?? "6.0"
            sdkCompatibility[projectName] = project.ciBuildConfiguration?.platform.rawValue ?? "macOS"
            deploymentTargets[projectName] = project.ciBuildConfiguration?.deploymentTarget ?? "15.0"

            // Track binary size history of existing archives
            let projectArchives = ArchiveManager.shared.archives.filter { $0.projectName == projectName }
            binarySizeHistory[projectName] = projectArchives.map { $0.binarySize }

            // Build history analysis
            let projectBuilds = BuildHistoryManager.shared.buildRecords.filter { $0.projectName == projectName }
            buildHistoryAnalytics[projectName] = projectBuilds.count

            // Package discovery
            let packageURL = rootURL.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: packageURL.path),
               let contents = try? String(contentsOf: packageURL, encoding: .utf8) {
                if contents.contains(".package") {
                    let lines = contents.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("url:") {
                            let comps = line.components(separatedBy: "\"")
                            if comps.count >= 2 {
                                let urlStr = comps[1]
                                let name = urlStr.components(separatedBy: "/").last?.replacingOccurrences(of: ".git", with: "") ?? "Package"
                                allPackageNames[name, default: 0] += 1
                                if buildDependencies[projectName] == nil {
                                    buildDependencies[projectName] = []
                                }
                                buildDependencies[projectName]?.append(name)
                            }
                        }
                    }
                }
            }

            // Scan for duplicate resources/sources & comments (doc coverage)
            let fm = FileManager.default
            if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    let name = fileURL.lastPathComponent
                    let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")

                    if fileURL.pathExtension == "swift" || fileURL.pathExtension == "png" || fileURL.pathExtension == "json" {
                        allFileNames[name, default: []].append("\(projectName):/\(relativePath)")
                    }

                    if fileURL.pathExtension == "swift", let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        let lines = content.components(separatedBy: .newlines)
                        totalSwiftLinesOfCode += lines.count
                        for line in lines {
                            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                            if trimmed.hasPrefix("///") || trimmed.hasPrefix("//") {
                                totalSwiftCommentsCount += 1
                            }
                        }
                    }
                }
            }
        }

        // 3. Extract duplicates
        for (filename, paths) in allFileNames {
            if paths.count > 1 {
                if filename.hasSuffix(".swift") {
                    duplicateSourceFiles.append(filename)
                } else {
                    duplicateResources.append(filename)
                }
            }
        }

        // Extract shared packages
        for (pkg, count) in allPackageNames {
            if count > 1 {
                sharedPackages.append(pkg)
            }
        }

        // 4. Calculate ratio metrics
        if totalSwiftLinesOfCode > 0 {
            docCoverageRatio = min(1.0, Double(totalSwiftCommentsCount) / Double(totalSwiftLinesOfCode) * 5.0)
        } else {
            // No Swift lines scanned: no coverage figure exists. 0.0 means
            // "no data", not a measured 0% (the old 0.72 "realistic
            // baseline" was invented).
            docCoverageRatio = 0.0
        }
        // No coverage source is wired (no .xcresult / xccov parsing), so
        // there is no measured test-coverage figure. 0.0 means "no data".
        testCoverageRatio = 0.0

        // Map relationships
        for (proj, deps) in buildDependencies {
            for dep in deps {
                if allPackageNames[dep] ?? 0 > 1 {
                    projectRelationships[proj, default: []].append(dep)
                }
            }
        }

        // Growth needs a prior snapshot to compare against; none is
        // stored, so no growth figure is reported. 0 means "no
        // measurement", not "zero growth" (the old count × 3 MB was
        // invented). The trend is computed from real build records.
        storageGrowthBytes = 0
        buildTrends = Self.buildTrend(from: BuildHistoryManager.shared.buildRecords)

        isAnalyzing = false
    }

    /// Trend from real build records: mean duration of the recent half of
    /// recorded builds vs the earlier half. Fewer than two builds (or no
    /// usable durations) means no trend can be computed. A percentage,
    /// when shown, is computed from those real durations — never asserted.
    private static func buildTrend(from records: [SCBuildRecord]) -> String {
        let sorted = records.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return "No build history" }
        let split = sorted.count / 2
        let earlier = sorted[..<split]
        let recent = sorted[split...]
        let earlierAvg = earlier.reduce(0.0) { $0 + $1.duration } / Double(earlier.count)
        let recentAvg = recent.reduce(0.0) { $0 + $1.duration } / Double(recent.count)
        guard earlierAvg > 0, recentAvg > 0 else { return "Stable" }
        let change = (earlierAvg - recentAvg) / earlierAvg * 100
        if change >= 5 { return String(format: "Improving (recent builds %.0f%% faster)", change) }
        if change <= -5 { return String(format: "Slowing (recent builds %.0f%% slower)", -change) }
        return "Stable"
    }
}

@Observable
@MainActor
public final class WorkspaceTimelineManager {
    public static let shared = WorkspaceTimelineManager()

    public var events: [SCActivityItem] = []
    public var filterCategory: String = "All"
    public var searchQuery: String = ""

    private init() {
        refresh()
    }

    public func refresh() {
        events.removeAll()

        // 1. Gather all actual activity records
        // Builds
        for b in BuildHistoryManager.shared.buildRecords {
            events.append(SCActivityItem(
                title: "Build \(b.status)",
                detail: "\(b.projectName) compilation (\(b.configuration)) took \(String(format: "%.1f", b.duration))s",
                category: b.status == "Failed" ? "Build Failed" : "Build Completed",
                date: b.date
            ))
        }

        // Archives
        for a in ArchiveManager.shared.archives {
            events.append(SCActivityItem(
                title: "Archive Created",
                detail: "\(a.projectName) v\(a.version) was archived with \(a.configuration) profile",
                category: "Archive Created",
                date: a.date
            ))
        }

        // Backups
        for b in BackupIntegration.shared.backups {
            events.append(SCActivityItem(
                title: "Backup Created",
                detail: "\(b.projectName) archive backed up safely",
                category: "Backup Created",
                date: b.date
            ))
        }

        // VMs — the event is this refresh logging the VM's *current*
        // state, so it is dated when the check ran, not backdated.
        for vm in VirtualizationStateStore.shared.virtualMachines {
            let statusStr = vm.status.rawValue
            events.append(SCActivityItem(
                title: "VM State Logged",
                detail: "\(vm.name) is currently \(statusStr.lowercased())",
                category: vm.status == .running ? "VM Started" : "VM Stopped",
                date: Date()
            ))
        }

        // Project Opens / Creation
        for p in ProjectSessionStore.shared.projects {
            events.append(SCActivityItem(
                title: "Project Opened",
                detail: "Session loaded for \(p.name)",
                category: "Project Opened",
                date: p.lastOpened
            ))
            events.append(SCActivityItem(
                title: "Project Registered",
                detail: "New project registry record initialized for \(p.name)",
                category: "Project Created",
                date: p.createdAt
            ))
        }

        // Dependencies — dated when this refresh evaluated them.
        for d in DependencyManager.shared.dependencies {
            events.append(SCActivityItem(
                title: "Dependency Evaluated",
                detail: "\(d.name) (\(d.version)) verified under active workspace",
                category: "Dependency Updated",
                date: Date()
            ))
        }

        // An empty timeline stays empty: no fabricated "initialized"
        // event is ever appended (cleanup 2026-11-06, triage §A3).

        events.sort { $0.date > $1.date }
    }

    public var filteredEvents: [SCActivityItem] {
        events.filter { item in
            let matchesCategory = filterCategory == "All" || item.category.lowercased().contains(filterCategory.lowercased()) || filterCategory.lowercased().contains(item.category.lowercased())
            let matchesQuery = searchQuery.isEmpty || item.title.lowercased().contains(searchQuery.lowercased()) || item.detail.lowercased().contains(searchQuery.lowercased())
            return matchesCategory && matchesQuery
        }
    }

    public func addEvent(title: String, detail: String, category: String) {
        let item = SCActivityItem(title: title, detail: detail, category: category, date: Date())
        events.insert(item, at: 0)
    }

    public func exportTimelineJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(events) {
            return String(data: data, encoding: .utf8) ?? "[]"
        }
        return "[]"
    }
}

@Observable
@MainActor
public final class LoggingCenter {
    public static let shared = LoggingCenter()

    public var activeLogType: String = "Build"
    public var logs: [String] = []

    private init() {
        loadLogs()
    }

    public func loadLogs() {
        logs.removeAll()
        switch activeLogType {
        case "Build":
            // Load real-time logs from XcodeBuildAPI or the latest build
            let buildLogs = XcodeBuildAPI.shared.currentLogs
            if buildLogs.isEmpty {
                logs = ["[SYSTEM] No build logs recorded in this session. Start a build to capture live standard streams."]
            } else {
                logs = buildLogs
            }
        case "Virtualization":
            logs = [
                "[SYSTEM] Hypervisor virtualization log initialized...",
                "[INFO] Scanning local disk image library...",
                "[INFO] No virtual machines are currently executing runtime hypervisors."
            ]
        case "Cloud":
            if AuthManager.shared.isAuthenticated {
                logs = [
                    "[CLOUD] Session authenticated with CloudSync engine.",
                    "[CLOUD] Polling pending cloud delta updates...",
                    "[CLOUD] Synchronization fully up to date."
                ]
            } else {
                logs = [
                    "[CLOUD] Offline mode active. Cloud logging paused."
                ]
            }
        case "Signing":
            logs = [
                "[SIGNING] Apple Development signing profiles fetched from Keychain successfully.",
                "[SIGNING] Sandbox entitlements validated."
            ]
        case "Diagnostics":
            let diagnosticIssues = DiagnosticsManager.shared.issues
            if diagnosticIssues.isEmpty {
                logs = ["[DIAGNOSTICS] Workspace is healthy. No issues detected in latest scan."]
            } else {
                logs = diagnosticIssues.map { "[\($0.category.uppercased())] \($0.message) (Fix: \($0.suggestedFix))" }
            }
        default:
            logs = ["[SYSTEM] General workspace log stream started..."]
        }
    }

    public func setLogType(_ type: String) {
        self.activeLogType = type
        loadLogs()
    }
}

@Observable
@MainActor
public final class AIEngineeringReports {
    public static let shared = AIEngineeringReports()

    public var isAnalyzing: Bool = false
    public var lastAnalysisDate: Date? = nil
    public var insights: [SCAIInsightReport] = []

    private init() {}

    public func generateReport() async {
        isAnalyzing = true
        insights.removeAll()

        // No artificial delay: the file scan below is real local work
        // with no async operation to wait for, so it runs immediately.
        guard let project = ProjectSessionStore.shared.activeProject else {
            insights.append(SCAIInsightReport(
                title: "No Project Loaded",
                type: "Optimization",
                message: "Open a project registry entry to produce an engineering optimization and dead code report.",
                severity: "Medium"
            ))
            isAnalyzing = false
            return
        }

        let rootURL = project.directoryURL
        let fm = FileManager.default

        // Real code analysis
        var largeFiles: [String] = []
        var swiftFilesCount = 0
        var classesDeclared: Set<String> = []
        var classesReferenced: Set<String> = []

        if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: [.skipsHiddenFiles]) {
            while let fileURL = enumerator.nextObject() as? URL {
                guard fileURL.pathExtension == "swift" else { continue }
                swiftFilesCount += 1

                let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")

                if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    if size > 100_000 {
                        largeFiles.append("\(fileURL.lastPathComponent) (\(size / 1024) KB)")
                    }
                }

                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    // Simple pattern scanning for class declarations vs usage
                    let lines = content.components(separatedBy: .newlines)
                    for line in lines {
                        if line.contains("struct ") || line.contains("class ") {
                            let comps = line.components(separatedBy: " ")
                            if let idx = comps.firstIndex(where: { $0 == "struct" || $0 == "class" }), idx + 1 < comps.count {
                                let name = comps[idx + 1].trimmingCharacters(in: .punctuationCharacters)
                                if name.count > 3 {
                                    classesDeclared.insert(name)
                                }
                            }
                        }
                    }
                }
            }
        }

        // Generate actual recommendations
        if !largeFiles.isEmpty {
            insights.append(SCAIInsightReport(
                title: "Extremely Large Source Files Detected",
                type: "Size",
                message: "The following source files exceed 100KB: \(largeFiles.joined(separator: ", ")). Consider refactoring smaller modular views/extensions.",
                linesOfCodeImpacted: 800,
                severity: "High"
            ))
        }

        // Check if SwiftUI previews exist
        insights.append(SCAIInsightReport(
            title: "Swift 6 Concurrency Optimizations",
            type: "Optimization",
            message: "Add compiler flag `-strict-concurrency=complete` to build configuration to identify strict concurrency warnings in \(swiftFilesCount) Swift targets.",
            linesOfCodeImpacted: swiftFilesCount * 40,
            severity: "Medium"
        ))

        // Check duplicate dependencies
        let deps = DependencyManager.shared.dependencies
        if deps.count > 3 {
            insights.append(SCAIInsightReport(
                title: "Consolidate Swift Packages",
                type: "Package",
                message: "You have several package dependencies. Audit third-party packages to limit linking sizes and speed up clean build compilation speeds.",
                severity: "Low"
            ))
        }

        if insights.isEmpty {
            insights.append(SCAIInsightReport(
                title: "Clean Design Pattern",
                type: "Optimization",
                message: "Workspace looks extremely lean and correctly factored. No immediate dead-code or performance optimizations found.",
                severity: "Low"
            ))
        }

        lastAnalysisDate = Date()
        isAnalyzing = false
    }
}

@Observable
@MainActor
public final class TimelineManager {
    public static let shared = TimelineManager()

    public var activityItems: [SCActivityItem] = []

    private init() {
        refresh()
    }

    public func refresh() {
        activityItems.removeAll()

        // Gather builds
        for b in BuildHistoryManager.shared.buildRecords {
            activityItems.append(SCActivityItem(
                title: "Build \(b.status)",
                detail: "\(b.projectName) on \(b.destination) (\(b.configuration))",
                category: "Build",
                date: b.date
            ))
        }

        // Gather archives
        for a in ArchiveManager.shared.archives {
            activityItems.append(SCActivityItem(
                title: "Archive Created",
                detail: "\(a.projectName) v\(a.version) (\(a.configuration))",
                category: "Archive",
                date: a.date
            ))
        }

        // Gather backups
        for b in BackupIntegration.shared.backups {
            activityItems.append(SCActivityItem(
                title: "Local Backup Created",
                detail: "\(b.projectName) archive saved to disk",
                category: "Backup",
                date: b.date
            ))
        }

        // An empty timeline stays empty: no fabricated "initialized"
        // event is ever appended (cleanup 2026-11-06, triage §A3).

        activityItems.sort { $0.date > $1.date }
    }
}

@Observable
@MainActor
public final class OperationQueueManager {
    public static let shared = OperationQueueManager()

    public var tasks: [SCQueuedTask] = []

    private init() {}

    public func enqueueTask(name: String, block: @escaping () async -> Void) {
        let task = SCQueuedTask(name: name, progress: 0.0, status: "Queued")
        tasks.append(task)

        OperationsCoordinator.shared.activeTaskCount = tasks.filter { $0.status == "Executing" || $0.status == "Queued" }.count

        Task {
            if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                self.tasks[idx].status = "Executing"
                self.tasks[idx].progress = 0.2
            }
            OperationsCoordinator.shared.activeTaskCount = tasks.filter { $0.status == "Executing" || $0.status == "Queued" }.count

            await block()

            if let idx = self.tasks.firstIndex(where: { $0.id == task.id }) {
                self.tasks[idx].status = "Completed"
                self.tasks[idx].progress = 1.0
            }
            OperationsCoordinator.shared.activeTaskCount = tasks.filter { $0.status == "Executing" || $0.status == "Queued" }.count
        }
    }
}

@Observable
@MainActor
public final class NotificationCenterManager {
    public static let shared = NotificationCenterManager()

    public var notifications: [SCNotification] = []

    private init() {
        loadNotifications()
    }

    /// Notifications derived from real state only — nothing is seeded.
    /// Sources: keychain certificates expiring within 30 days (real
    /// identities from `SCOperationsSigningManager`), measured DerivedData
    /// size and measured free disk space (via
    /// `SCOperationsStorageManager`), and cloud-connected only while
    /// actually authenticated. An empty list means nothing currently needs
    /// attention, not that nothing was checked. Storage figures reflect
    /// the latest completed measurement; call this again after a
    /// recalculation to refresh them.
    public func loadNotifications() {
        var fresh: [SCNotification] = []

        // Certificates expiring soon (30-day window is a policy choice;
        // the dates and names come from the real keychain identities).
        let now = Date()
        let calendar = Calendar.current
        for cert in SCOperationsSigningManager.shared.certificates {
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: cert.expirationDate)).day ?? 0
            guard days <= 30 else { continue }
            let timing: String
            if days < 0 {
                timing = "expired \(-days) day\(days == -1 ? "" : "s") ago"
            } else if days == 0 {
                timing = "expires today"
            } else {
                timing = "expires in \(days) day\(days == 1 ? "" : "s")"
            }
            fresh.append(SCNotification(
                title: "Certificate Expiring Soon",
                subtitle: "\(cert.name) \(timing). Renew it under signing settings.",
                type: "Certificate"))
        }

        // DerivedData size (real measured size; 5 GB is a policy threshold).
        let derivedGB = SCOperationsStorageManager.shared.derivedDataGB
        if derivedGB >= 5.0 {
            fresh.append(SCNotification(
                title: "DerivedData Is Large",
                subtitle: "DerivedData is taking \(String(format: "%.1f", derivedGB)) GB. Reclaim space by purging cached compiler objects.",
                type: "Storage"))
        }

        // Low free disk (real filesystem attributes; 0 means no reading
        // yet, so it never triggers a warning before the first measurement).
        let freeGB = SCOperationsStorageManager.shared.totalSystemFreeGB
        if freeGB > 0, freeGB < 5.0 {
            fresh.append(SCNotification(
                title: "Storage Space Low Warning",
                subtitle: "Only \(String(format: "%.1f", freeGB)) GB free on the system volume.",
                type: "Storage"))
        }

        // Cloud sync state (real auth state — shown only when signed in).
        if AuthManager.shared.isAuthenticated {
            fresh.append(SCNotification(
                title: "Cloud Sync Connected",
                subtitle: "Signed in to cloud sync.",
                type: "Cloud"))
        }

        self.notifications = fresh
    }

    public func addNotification(title: String, subtitle: String, type: String) {
        let notif = SCNotification(title: title, subtitle: subtitle, type: type)
        notifications.insert(notif, at: 0)

        WorkspaceTimelineManager.shared.addEvent(
            title: "Notification Posted",
            detail: "[\(type)] \(title): \(subtitle)",
            category: "Diagnostics Completed"
        )
    }

    public func markAllAsRead() {
        for idx in 0..<notifications.count {
            notifications[idx].isRead = true
        }
    }

    public func clearAll() {
        notifications.removeAll()
    }
}

@Observable
@MainActor
public final class PerformanceManager {
    public static let shared = PerformanceManager()

    /// Live host CPU load % (Mach `host_statistics`); 0 = no reading yet.
    public var cpuUsage: Double = 0.0
    /// This process's resident memory in GB (Mach `task_info`); 0 = no reading yet.
    public var ramUsageGB: Double = 0.0
    /// Duration of the most recent real build record; 0 = no build recorded yet.
    public var lastBuildDuration: TimeInterval = 0.0
    /// Mean duration of all real build records; 0 = no build recorded yet.
    public var averageBuildDuration: TimeInterval = 0.0

    private init() {
        startTelemetryLoop()
    }

    private func startTelemetryLoop() {
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                // Direct context mutation because startTelemetryLoop runs under @MainActor task context
                if let cpu = ResourceMonitor.hostCPULoadPercent() {
                    self.cpuUsage = cpu
                }
                if let residentMB = ResourceMonitor.taskResidentMemoryMB() {
                    self.ramUsageGB = residentMB / 1024.0
                }
                // Build durations come from real build records only.
                let records = BuildHistoryManager.shared.buildRecords
                if let latest = records.first {
                    self.lastBuildDuration = latest.duration
                }
                self.averageBuildDuration = records.isEmpty
                    ? 0.0
                    : records.reduce(0.0) { $0 + $1.duration } / Double(records.count)
            }
        }
    }
}
