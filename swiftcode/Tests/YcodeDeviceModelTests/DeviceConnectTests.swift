import Foundation
import Testing
@testable import YcodeDeviceModel

@Suite struct DeviceConnectTests {
    @Test func buildParserSplitsErrorsAndWarnings() {
        let text = """
        /Users/dylan/App.swift:12:7: error: cannot find 'Foo' in scope
        /Users/dylan/App.swift:20:3: warning: unused variable 'bar'
        note: some other line
        """
        let result = BuildParser.parseXcodebuildOutput(text)
        #expect(result.errors.count == 1)
        #expect(result.errors[0].filePath == "/Users/dylan/App.swift")
        #expect(result.errors[0].line == 12)
        #expect(result.errors[0].message == "cannot find 'Foo' in scope")
        #expect(result.errors[0].isError)
        #expect(result.warnings.count == 1)
        #expect(result.warnings[0].line == 20)
        #expect(!result.warnings[0].isError)
    }

    @Test func deviceParserDecodesXCDeviceList() {
        let json = """
        [
          {"name": "Dylan's iPhone", "model": "iPhone 17 Pro", "platform": "iOS",
           "operatingSystemVersion": "26.1", "identifier": "00008110-1111111111111111",
           "modelUTI": "com.apple.iphone-17-pro", "isWirelesslyConnected": false,
           "isConnected": true, "isAvailable": true},
          {"name": "Nameless", "identifier": null},
          {"name": "Old iPad", "model": "iPad", "platform": "iPadOS",
           "operatingSystemVersion": "26.0", "identifier": "00008110-2222222222222222"}
        ]
        """
        let devices = DeviceParser.parseXCDeviceList(json)
        #expect(devices.count == 2)
        #expect(devices[0].name == "Dylan's iPhone")
        #expect(devices[0].udid == "00008110-1111111111111111")
        #expect(devices[0].osVersion == "26.1")
        #expect(devices[1].platform == "iPadOS")
    }

    @Test func deviceParserReturnsEmptyForGarbage() {
        #expect(DeviceParser.parseXCDeviceList("not json").isEmpty)
        #expect(DeviceParser.parseXCDeviceList("").isEmpty)
    }

    @Test func logParserClassifiesSeverity() {
        #expect(LogParser.parseLogLine("[error] boom", type: .runtime).severity == .error)
        #expect(LogParser.parseLogLine("warning: low memory", type: .runtime).severity == .warning)
        #expect(LogParser.parseLogLine("[debug] tick", type: .runtime).severity == .debug)
        #expect(LogParser.parseLogLine("all good", type: .build).severity == .info)
        #expect(LogParser.parseLogLine("[MySubsystem] hello", type: .build).category == "MySubsystem")
    }

    @Test func outputFormatterStripsANSIAndFormatsBytes() {
        #expect(OutputFormatter.stripANSIColorCodes("\u{1B}[31mred\u{1B}[0m") == "red")
        #expect(OutputFormatter.formatBytes(500) == "0 KB")
        #expect(OutputFormatter.formatBytes(2_048) == "2 KB")
        #expect(OutputFormatter.formatBytes(3 * 1024 * 1024) == "3.0 MB")
        #expect(OutputFormatter.formatBytes(2.5 * 1024 * 1024 * 1024) == "2.50 GB")
    }

    @Test func diagnosticsFormatterReportsMissingXcode() {
        let env = DeviceEnvironment(macOSVersion: "26.1")
        let diagnostics = DiagnosticsFormatter.formatEnvironmentDiagnostics(env)
        #expect(diagnostics.contains { $0.contains("Xcode is not detected") })
        #expect(diagnostics.contains { $0.contains("iOS SDK") })
    }

    @Test func diagnosticsFormatterPassesCleanEnvironment() {
        let env = DeviceEnvironment(
            xcodePath: "/Applications/Xcode.app",
            xcodeVersion: "27.1",
            macOSVersion: "26.1",
            hasiOSSDK: true,
            hasSimulatorSDK: true,
            isSigningSetup: true)
        #expect(DiagnosticsFormatter.formatEnvironmentDiagnostics(env) == ["All checks passed. System is fully compatible with DeviceConnect deployment pipelines."])
    }

    @Test func deviceMetricsUnavailableIsMarked() {
        #expect(!DeviceMetrics.unavailable.isAvailable)
        #expect(DeviceMetrics().isAvailable)
    }

    @Test func processRunnerCapturesEchoOutput() async throws {
        let result = try await DeviceConnectProcessRunner.shared.run(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello", "device"])
        #expect(result.exitCode == 0)
        #expect(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello device")
    }

    @Test func processRunnerThrowsForMissingExecutable() async {
        await #expect(throws: DeviceConnectProcessError.self) {
            try await DeviceConnectProcessRunner.shared.run(
                executableURL: URL(fileURLWithPath: "/bin/definitely-not-a-real-tool"),
                arguments: [])
        }
    }

    @Test func processRunnerStreamsLinesLive() async throws {
        let box = LineBox()
        let success = try await DeviceConnectProcessRunner.shared.runStreamingAsync(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["streamed"],
            onStdout: { line in box.append(line) },
            onStderr: { _ in })
        #expect(success)
        #expect(box.lines.contains("streamed"))
    }
}

private final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []
    var lines: [String] { lock.withLock { storage } }
    func append(_ line: String) { lock.withLock { storage.append(line) } }
}
