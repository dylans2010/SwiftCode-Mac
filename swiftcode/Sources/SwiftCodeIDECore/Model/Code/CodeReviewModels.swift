import Foundation

public struct CodeReviewResult: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let fileName: String
    public let reviewedAt: Date
    public let overallScore: Int
    public let summary: String
    public var issues: [CodeReviewIssue]

    public init(fileName: String, reviewedAt: Date = Date(), overallScore: Int, summary: String, issues: [CodeReviewIssue] = []) {
        self.fileName = fileName
        self.reviewedAt = reviewedAt
        self.overallScore = overallScore
        self.summary = summary
        self.issues = issues
    }

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

public struct CodeReviewIssue: Identifiable, Codable, Sendable {
    public var id = UUID()
    public let severity: Severity
    public let category: Category
    public let lineNumber: Int?
    public let description: String
    public let suggestion: String
    public let codeSnippet: String?
    public var isResolved: Bool = false

    public init(severity: Severity, category: Category, lineNumber: Int? = nil, description: String, suggestion: String, codeSnippet: String? = nil, isResolved: Bool = false) {
        self.severity = severity
        self.category = category
        self.lineNumber = lineNumber
        self.description = description
        self.suggestion = suggestion
        self.codeSnippet = codeSnippet
        self.isResolved = isResolved
    }

    public enum Severity: String, Codable, CaseIterable, Sendable {
        case critical = "Critical"
        case warning = "Warning"
        case info = "Info"
        case style = "Style"

        public var icon: String {
            switch self {
            case .critical: return "exclamationmark.octagon.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .style: return "paintbrush.fill"
            }
        }
    }

    public enum Category: String, Codable, CaseIterable, Sendable {
        case performance = "Performance"
        case security = "Security"
        case architecture = "Architecture"
        case readability = "Readability"
        case logic = "Logic"
        case other = "Other"
    }
}
