import Foundation

public enum OrganizerSidebar {
    public struct Section: Equatable, Sendable {
        public var title: String
        public var pages: [String]
    }

    public static let sections: [Section] = [
        Section(title: "Products", pages: ["Archives"]),
        Section(title: "Insights", pages: ["Overview"]),
        Section(title: "Reports", pages: ["Crashes", "Disk Writes", "Energy", "Feedback", "Hangs", "Launches"]),
        Section(title: "Metrics", pages: ["Battery Usage", "Disk Writes", "Hang Rate", "Hitches", "Launch Time", "Memory", "Storage", "Terminations"]),
    ]

    public static var rows: [(section: String, page: String?)] {
        sections.flatMap { s in [(s.title, nil)] + s.pages.map { (s.title, $0) } }
    }

    public static func hasData(section: String) -> Bool { section == "Products" }

    public static func emptyState(page: String, version: String) -> (title: String, message: String) {
        ("No \(page) Data", "There is no \(page.lowercased()) data available for version \(version).")
    }
}
