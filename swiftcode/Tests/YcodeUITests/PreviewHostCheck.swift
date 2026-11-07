import Darwin
import Foundation
import Testing
@testable import YcodeIDECore
@testable import YcodeUI

struct PreviewHostCheckTrait: SuiteTrait, TestTrait, TestScoping {
    static let prefix = "SwiftCodePreview"

    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        guard !test.isSuite else { try await function(); return }
        var thrown: (any Error)?
        do { try await function() } catch { thrown = error }
        let left = ProcessAudit.leftovers(grace: 5) { $0.name.hasPrefix(Self.prefix) }
        if !left.isEmpty {
            Issue.record("\(test.name) left preview hosts running: \(left.map(\.description).joined(separator: ", "))")
            ProcessAudit.kill(left)
        }
        PreviewRenderer.stopMacHosts()
        if let thrown { throw thrown }
    }
}

extension Trait where Self == PreviewHostCheckTrait {
    static var previewHostCheck: Self { Self() }
}
