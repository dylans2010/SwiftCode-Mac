import Foundation
import Observation

public struct SCDiagnosticIssue: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let category: String // "Broken Reference", "Unused Asset", "Deprecated API", "Signing", "Concurrency"
    public let message: String
    public let filePath: String?
    public let suggestedFix: String

    public init(id: UUID = UUID(), category: String, message: String, filePath: String?, suggestedFix: String) {
        self.id = id
        self.category = category
        self.message = message
        self.filePath = filePath
        self.suggestedFix = suggestedFix
    }
}

public struct SCSecurityFinding: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let title: String
    public let severity: String // "Critical", "Warning", "Info"
    public let description: String
    public let filePath: String?
    public let suggestion: String

    public init(id: UUID = UUID(), title: String, severity: String, description: String, filePath: String?, suggestion: String) {
        self.id = id
        self.title = title
        self.severity = severity
        self.description = description
        self.filePath = filePath
        self.suggestion = suggestion
    }
}

@Observable
@MainActor
public final class DiagnosticsManager {
    public static let shared = DiagnosticsManager()

    public var isScanning: Bool = false
    public var lastScanDate: Date? = nil
    public var issues: [SCDiagnosticIssue] = []

    private init() {}

    public func scanWorkspace() async {
        isScanning = true
        issues.removeAll()

        guard let project = ProjectSessionStore.shared.activeProject else {
            issues.append(SCDiagnosticIssue(
                category: "Workspace",
                message: "No active project is currently loaded in the editor workspace.",
                filePath: nil,
                suggestedFix: "Select and open a project from the Project Registry or the Welcome Screen."
            ))
            lastScanDate = Date()
            isScanning = false
            return
        }

        let rootURL = project.directoryURL
        let projectFiles = project.files
        let hasBackups = !BackupIntegration.shared.backups.isEmpty

        // Run I/O operations and file reading off the main thread
        let scannedIssues = await Task.detached(priority: .background) {
            var found: [SCDiagnosticIssue] = []
            let fm = FileManager.default

            // 1. Broken References Scan
            for file in projectFiles {
                let fileURL = rootURL.appendingPathComponent(file.path)
                if !fm.fileExists(atPath: fileURL.path) {
                    found.append(SCDiagnosticIssue(
                        category: "Broken Reference",
                        message: "File reference '\(file.name)' is missing from the physical disk.",
                        filePath: file.path,
                        suggestedFix: "Remove the missing reference from the project file tree or restore the file at: \(file.path)"
                    ))
                }
            }

            // 2. Scan Swift files for deprecated APIs
            if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    guard fileURL.pathExtension == "swift" else { continue }
                    let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")

                    if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
                        if contents.contains("NSColor.windowBackground") {
                            found.append(SCDiagnosticIssue(
                                category: "Deprecated API",
                                message: "Hardcoded NSColor reference found. Use SwiftUI system materials.",
                                filePath: relativePath,
                                suggestedFix: "Replace with `Color(NSColor.windowBackgroundColor)` for strict dark/light compatibility."
                            ))
                        }
                        if contents.contains("DispatchQueue.global()") && !contents.contains("async") {
                            found.append(SCDiagnosticIssue(
                                category: "Concurrency",
                                message: "Legacy DispatchQueue background block. Prefer Swift 6 Structured Concurrency.",
                                filePath: relativePath,
                                suggestedFix: "Refactor to `Task` and use `async/await` blocks."
                            ))
                        }
                    }
                }
            }

            // 3. Signing plist check
            let infoPlistURL = rootURL.appendingPathComponent("Info.plist")
            if !fm.fileExists(atPath: infoPlistURL.path) {
                found.append(SCDiagnosticIssue(
                    category: "Signing",
                    message: "Missing standard Info.plist configuration file.",
                    filePath: "Info.plist",
                    suggestedFix: "Generate a generic Info.plist file to configure bundle identities and keys properly."
                ))
            }

            if !hasBackups {
                found.append(SCDiagnosticIssue(
                    category: "Workspace Health",
                    message: "No localized project backups found on disk.",
                    filePath: nil,
                    suggestedFix: "Configure automated local or remote backups inside cloud settings."
                ))
            }

            return found
        }.value

        self.issues = scannedIssues
        lastScanDate = Date()
        isScanning = false

        WorkspaceHealth.shared.recompute()
    }
}

@Observable
@MainActor
public final class SecurityManager {
    public static let shared = SecurityManager()

    public var isAuditing: Bool = false
    public var lastAuditDate: Date? = nil
    public var findings: [SCSecurityFinding] = []

    private init() {}

    public func runAudit() async {
        isAuditing = true
        findings.removeAll()

        guard let project = ProjectSessionStore.shared.activeProject else {
            findings.append(SCSecurityFinding(
                title: "No Project Loaded",
                severity: "Info",
                description: "Security auditing requires an active project to analyze source code for keys and secrets.",
                filePath: nil,
                suggestion: "Please load a project to trigger a source security scan."
            ))
            lastAuditDate = Date()
            isAuditing = false
            return
        }

        let rootURL = project.directoryURL
        let projectName = project.name

        let scannedFindings = await Task.detached(priority: .background) {
            var found: [SCSecurityFinding] = []
            let fm = FileManager.default

            // Secrets Scan (hardcoded API Keys / Tokens)
            if let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                while let fileURL = enumerator.nextObject() as? URL {
                    guard fileURL.pathExtension == "swift" || fileURL.pathExtension == "json" || fileURL.pathExtension == "plist" else { continue }
                    let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")

                    if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
                        let patterns = [
                            ("API_KEY", "Potential hardcoded API credentials"),
                            ("api_key", "Potential hardcoded API credentials"),
                            ("apiSecret", "Potential hardcoded credentials secret"),
                            ("githubToken", "Hardcoded personal github token risk")
                        ]
                        for (pattern, label) in patterns {
                            if contents.contains(pattern) {
                                found.append(SCSecurityFinding(
                                    title: label,
                                    severity: "Critical",
                                    description: "Found keyword '\(pattern)' inside source. This may leak sensitive deployment credentials.",
                                    filePath: relativePath,
                                    suggestion: "Move API credentials to the secure secure keychain or supply them via environment variables at compile-time."
                                ))
                            }
                        }
                    }
                }
            }

            // Sandbox/Entitlements Verification
            let entitlementsURL = rootURL.appendingPathComponent("\(projectName).entitlements")
            if !fm.fileExists(atPath: entitlementsURL.path) {
                found.append(SCSecurityFinding(
                    title: "App Sandbox Configuration",
                    severity: "Warning",
                    description: "No dedicated .entitlements file found in active compile targets.",
                    filePath: nil,
                    suggestion: "Create an entitlements file and enable App Sandbox to safeguard users during runtime."
                ))
            }

            return found
        }.value

        self.findings = scannedFindings
        lastAuditDate = Date()
        isAuditing = false

        WorkspaceHealth.shared.recompute()
    }
}

public struct SCCrashReport: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public let date: Date
    public let processName: String
    public let exceptionType: String
    public let crashLog: String

    public init(id: UUID = UUID(), date: Date = Date(), processName: String, exceptionType: String, crashLog: String) {
        self.id = id
        self.date = date
        self.processName = processName
        self.exceptionType = exceptionType
        self.crashLog = crashLog
    }
}

@Observable
@MainActor
public final class CrashReportManager {
    public static let shared = CrashReportManager()

    public var reports: [SCCrashReport] = []

    private init() {
        refreshReports()
    }

    public func refreshReports() {
        let fm = FileManager.default
        let libraryLogs = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/DiagnosticReports")
        if let contents = try? fm.contentsOfDirectory(at: libraryLogs, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
            self.reports = contents.prefix(5).map { url in
                SCCrashReport(
                    date: (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date(),
                    processName: url.lastPathComponent,
                    exceptionType: "EXC_BAD_INSTRUCTION",
                    crashLog: (try? String(contentsOf: url, encoding: .utf8)) ?? "No log detail readable."
                )
            }
        } else {
            self.reports = []
        }
    }
}

@Observable
@MainActor
public final class WorkspaceHealth {
    public static let shared = WorkspaceHealth()

    public var healthScore: Int = 100
    public var rating: String = "Excellent"

    private init() {
        recompute()
    }

    public func recompute() {
        var score = 100

        let issueCount = DiagnosticsManager.shared.issues.count
        score -= (issueCount * 8)

        let criticalCount = SecurityManager.shared.findings.filter { $0.severity == "Critical" }.count
        score -= (criticalCount * 15)

        let buildRecords = BuildHistoryManager.shared.buildRecords
        if !buildRecords.isEmpty {
            let failedBuilds = buildRecords.filter { $0.status == "Failed" }.count
            let failRatio = Double(failedBuilds) / Double(buildRecords.count)
            score -= Int(failRatio * 30.0)
        }

        if StorageManager.shared.cacheUsageGB > 20.0 {
            score -= 5
        }

        self.healthScore = max(0, min(100, score))

        if healthScore >= 90 {
            rating = "Excellent"
        } else if healthScore >= 75 {
            rating = "Good"
        } else if healthScore >= 50 {
            rating = "Fair"
        } else {
            rating = "Critical"
        }
    }
}
