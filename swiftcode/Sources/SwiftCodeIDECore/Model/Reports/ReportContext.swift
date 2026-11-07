import Foundation
import SwiftCodeBuild

public struct ReportContext: Equatable, Sendable {
    public var action = "Build"
    public var scheme: String?
    public var containerKind = "Project"
    public var containerName = ""
    public var configuration = "Debug"
    public var destination = ""
    public var duration: TimeInterval = 0
    public var issues: [Diagnostic] = []
    public var tests: [TestOutcome] = []
    public var plan: String?
    public var testTargets = 0
    public var testTarget: String?
    public var location: ReportLocation = .local
    public var sdk = ""
    public var coverage: [CoverageItem] = []
    public var logTimes: [TimeInterval] = []
    public var carriedOver: [BuildLogSection] = []
    public var kind: ReportKind {
        switch action {
        case "Test": .test
        case "Clean": .clean
        case "Analyze": .analyze
        case "Build": .build
        default: .package
        }
    }
    public init() {}
}

public enum ReportFormat {
    public static func dayAndTime(_ d: Date) -> String {
        let day = DateFormatter()
        day.dateStyle = .medium
        day.timeStyle = .none
        day.doesRelativeDateFormatting = true
        var dayText = day.string(from: d)
        #if os(Linux)
        let cal = Calendar.current
        if cal.isDateInToday(d) { dayText = "Today" } else if cal.isDateInYesterday(d) { dayText = "Yesterday" }
        #endif
        let time = DateFormatter()
        time.dateStyle = .none
        time.timeStyle = .short
        return "\(dayText), \(time.string(from: d))"
    }

    public static func footerDate(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d/yy"
        let t = DateFormatter()
        t.dateStyle = .none
        t.timeStyle = .short
        return "\(f.string(from: d)), \(t.string(from: d))"
    }

    public static func seconds(_ s: TimeInterval) -> String { String(format: "%.1f", s) }
}
