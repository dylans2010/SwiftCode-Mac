import XCTest
@testable import SwiftCodeSDK

/// Build output parser grammars and the truthful-success rule.
final class SDKBuildParserTests: XCTestCase {
    func testLocatedError() {
        let output = "/Users/user/App.swift:42:7: error: cannot find 'foo' in scope\n"
        let parsed = SDKBuildOutputParser.parse(output)
        XCTAssertEqual(parsed.errorCount, 1)
        XCTAssertEqual(parsed.diagnostics.first?.file, "/Users/user/App.swift")
        XCTAssertEqual(parsed.diagnostics.first?.line, 42)
        XCTAssertTrue(parsed.diagnostics.first?.message.contains("cannot find") == true)
    }

    func testLocatedWarningWithoutColumn() {
        let output = "Sources/App.swift:10: warning: unused variable\n"
        let parsed = SDKBuildOutputParser.parse(output)
        XCTAssertEqual(parsed.warningCount, 1)
        XCTAssertEqual(parsed.errorCount, 0)
        XCTAssertEqual(parsed.diagnostics.first?.line, 10)
    }

    func testPlainErrorAndXcodebuildPrefix() {
        let output = "error: build input file cannot be found\nxcodebuild: error: scheme not found\n"
        let parsed = SDKBuildOutputParser.parse(output)
        XCTAssertEqual(parsed.errorCount, 2)
    }

    func testLdLines() {
        let output = "ld: library not found for -lFoo\nld: warning: directory not found\n"
        let parsed = SDKBuildOutputParser.parse(output)
        XCTAssertEqual(parsed.errorCount, 1)
        XCTAssertEqual(parsed.warningCount, 1)
    }

    func testBuildFailedMarkerCountsAsError() {
        let parsed = SDKBuildOutputParser.parse("** BUILD FAILED **\n")
        XCTAssertEqual(parsed.errorCount, 1)
    }

    func testDidSucceedRequiresAllThree() {
        let good = "** BUILD SUCCEEDED **\n"
        let parsedGood = SDKBuildOutputParser.parse(good)
        XCTAssertTrue(SDKBuildOutputParser.didSucceed(output: good, exitCode: 0, parsed: parsedGood))
        // Non-zero exit: not a success even with the marker.
        XCTAssertFalse(SDKBuildOutputParser.didSucceed(output: good, exitCode: 1, parsed: parsedGood))
        // Missing marker: not a success even with exit 0.
        let noMarker = SDKBuildOutputParser.parse("")
        XCTAssertFalse(SDKBuildOutputParser.didSucceed(output: "", exitCode: 0, parsed: noMarker))
        // Errors present: not a success even with exit 0 + marker.
        let withError = "** BUILD SUCCEEDED **\nerror: something broke\n"
        let parsedError = SDKBuildOutputParser.parse(withError)
        XCTAssertFalse(SDKBuildOutputParser.didSucceed(output: withError, exitCode: 0, parsed: parsedError))
    }

    func testDiagnosticsAreCapped() {
        let output = (0..<100).map { "error: problem \($0)" }.joined(separator: "\n")
        let parsed = SDKBuildOutputParser.parse(output, maxDiagnostics: 50)
        XCTAssertEqual(parsed.diagnostics.count, 50)
        XCTAssertEqual(parsed.errorCount, 100)
    }
}
