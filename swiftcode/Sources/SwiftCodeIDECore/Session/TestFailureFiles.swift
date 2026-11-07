import Foundation
import SwiftCodeBuild

public enum TestFailureFiles {
    public static func resolve(_ outcomes: [TestOutcome], tests: [DiscoveredTest]) -> [TestOutcome] {
        outcomes.map { o in
            var o = o
            o.failures = o.failures.map { d in
                guard var loc = d.location, !loc.file.hasPrefix("/") else { return d }
                let name = (loc.file as NSString).lastPathComponent
                let own = tests.first { $0.matches(o) && ($0.file as NSString).lastPathComponent == name }
                guard let file = (own ?? tests.first { ($0.file as NSString).lastPathComponent == name })?.file else { return d }
                var d = d
                loc.file = file
                d.location = loc
                return d
            }
            return o
        }
    }
}
