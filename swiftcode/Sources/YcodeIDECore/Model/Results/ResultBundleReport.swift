import Foundation
import YcodeBuild
import YcodeXcodebuild

public enum ResultBundleReport {
    public static func outcome(_ t: XCResultReader.Test) -> TestOutcome {
        let parts = t.identifier.split(separator: "/").map(String.init)
        let last = parts.last ?? t.name
        let name = last.hasSuffix("()") ? String(last.dropLast(2)) : last
        let suite = parts.count > 1 ? parts[parts.count - 2] : nil
        let status: TestOutcome.Status = switch t.status {
        case "Failure": .failed
        case "Skipped": .skipped
        default: .passed
        }
        let failures = t.failures.map { f in
            Diagnostic(severity: .error, message: f.message, location: f.file.map { Diagnostic.Location(file: $0, line: f.line ?? 0) })
        }
        return TestOutcome(suite: suite, name: name, status: status, failures: failures, duration: t.duration)
    }

    public static func report(_ bundle: URL) throws -> BuildReport {
        let reader = try XCResultReader(bundle)
        let outcomes = try reader.tests().map(outcome)
        let failed = outcomes.filter { $0.status == .failed }
        let created = (try? bundle.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        var r = BuildReport(title: "Test \(bundle.deletingPathExtension().lastPathComponent)", date: created, succeeded: failed.isEmpty,
                            log: ["SwiftCode: read \(outcomes.count) tests from \(bundle.path)"], errorCount: failed.count, warningCount: 0)
        r.context.action = "Test"
        r.context.tests = outcomes
        r.context.issues = failed.flatMap(\.failures)
        return r
    }
}

extension WorkspaceSession {
    @discardableResult
    public func openResultBundle(_ bundle: URL) throws -> BuildReport {
        let r = try ResultBundleReport.report(bundle)
        recordReport(r)
        return r
    }
}
