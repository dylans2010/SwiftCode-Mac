import Foundation
import SwiftCodeBuild

public struct TestReportFilters: Equatable, Sendable {
    public var failedRunsOnly = false
    public var device: String?
    public var configuration: String?
    public var tag: String?
    public init() {}

    public static let untagged = "Untagged Tests"
    public static let configurationTitle = "Test Scheme Action"

    public static func menus(_ r: BuildReport) -> [(title: String, items: [String])] {
        let titles = TestReportModel.filterTitles(r)
        let device = r.context.destination.isEmpty ? "My Mac" : r.context.destination
        return [(titles[0], ["All Tests", "Failed Tests Only"]), (titles[1], ["All Runs", "Failed Runs Only"]),
                (titles[2], ["All Run Destinations", device]), (titles[3], ["All Configurations", configurationTitle]),
                (titles[4], ["All Tags", untagged])]
    }

    public func rows(_ r: BuildReport, failedOnly: Bool, text: String) -> [TestReportModel.TestRow] {
        let device = r.context.destination.isEmpty ? "My Mac" : r.context.destination
        if let d = self.device, d != device { return [] }
        if let c = configuration, c != Self.configurationTitle { return [] }
        if let t = tag, t != Self.untagged { return [] }
        return TestReportModel.testRows(r, failedOnly: failedOnly || failedRunsOnly, text: text)
    }
}
