import Foundation

// MARK: - Code Review Result

public struct CodeReviewResult: Identifiable, Codable {
    public var id = UUID()
    public let fileName: String
    public let reviewedAt: Date
    public let overallScore: Int
    public let summary: String
    public var issues: [CodeReviewIssue]

    public var criticalCount: Int {
        issues.filter { $0.severity == .critical }.count
    }

    public var warningCount: Int {
        issues.filter { $0.severity == .warning }.count
    }

    public var unresolvedCount: Int {
        issues.filter { !$0.isResolved }.count
    }
}

// MARK: - Code Review Issue

public struct CodeReviewIssue: Identifiable, Codable {
    public var id = UUID()
    public let severity: Severity
    public let category: Category
    public let lineNumber: Int?
    public let description: String
    public let suggestion: String
    public let codeSnippet: String?
    public var isResolved: Bool = false

    public enum Severity: String, Codable, CaseIterable {
        case critical = "Critical"
        case warning = "Warning"
        case info = "Info"
        case style = "Style"

        public var icon: String {
            switch self {
            case .critical: return "exclamationmark.octagon.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .info:     return "info.circle.fill"
            case .style:    return "paintbrush.fill"
            }
        }
    }

    public enum Category: String, Codable, CaseIterable {
        case performance = "Performance"
        case security = "Security"
        case architecture = "Architecture"
        case readability = "Readability"
        case logic = "Logic"
        case other = "Other"
    }
}
