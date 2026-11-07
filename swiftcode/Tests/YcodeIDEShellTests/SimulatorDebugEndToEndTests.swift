import Foundation
import Testing
import YcodeBuild
import YcodeDebug
@testable import YcodeIDECore
@testable import YcodeIDEShell
import YcodeSimLink

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["SWIFTCODE_SIM_DEBUG_E2E"] != nil))
struct SimulatorDebugEndToEndTests {
    static let env = ProcessInfo.processInfo.environment
    static let handlerLine = 72

    static var samples: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/DebugSamples")
    }

    var watched: WorkspaceShellModel?

    func wait(_ what: String, seconds: Double, _ condition: () -> Bool) async -> Bool {
        let start = Date()
        var reported = start
        while !condition(), Date().timeIntervalSince(start) < seconds {
            try? await Task.sleep(for: .milliseconds(250))
            if let m = watched, Date().timeIntervalSince(reported) > 30 {
                reported = Date()
                print("e2e: waiting for \(what) (\(Int(reported.timeIntervalSince(start))) s): activity \"\(m.activityText)\", console tail: "
                      + m.session.console.split(separator: "\n").suffix(3).joined(separator: " | "))
            }
        }
        #expect(condition(), "timed out waiting for \(what)")
        return condition()
    }

    func value(_ m: WorkspaceShellModel, _ name: String) -> String? {
        m.debug.variables.first { $0.name == name }?.value
    }

    func tap(_ address: String) async throws {
        let point = try await Task.detached { try SimDeviceTap.tap(address: address) }.value
        print("e2e: tapped \(point)")
    }

    @Test mutating func aBreakpointInTheButtonHandlerStopsShowsVariablesAndContinues() async throws {
        let spec = try #require(Self.env["SWIFTCODE_SIM_DEBUG_E2E"]).split(separator: "/").map(String.init)
        try #require(spec.count == 2)
        let (host, device) = (spec[0], spec[1])
        let display = try #require(Self.env["SWIFTCODE_SIM_DEBUG_E2E_DISPLAY"])
        let source = Self.samples.appendingPathComponent("TapCounter/TapCounter.swift").path
        let m = try WorkspaceShellModel(url: Self.samples.appendingPathComponent("DebugSamples.xcodeproj"))
        watched = m
        m.destination = ShellRemoteRun.destination(host: host, device: LinkDeviceInfo(name: device, deviceType: "iphone-duo",
                                                                                    runtime: "/rt/iOS-27.1/RuntimeRoot", state: "shutdown"))
        m.perform(.deleteAllBreakpoints)
        m.debug.gutterClick(file: source, line: Self.handlerLine)
        defer {
            if let h = try? LinkClient().host(named: host), let c = try? LinkClient().control(h) {
                _ = try? c.request(LinkRequest(op: "shutdown", device: device))
                c.close()
            }
        }

        let t0 = Date()
        let run = Task { await m.run() }
        guard await wait("the app under the debugger", seconds: 1500, {
            m.session.isDebuggingSimulatorStub && !m.debug.isPaused && m.activityText.hasPrefix("Running TapCounter")
        }) else {
            print("e2e: console:\n\(m.session.console)")
            m.stop()
            return
        }
        await run.value
        print("e2e: running under the debugger after \(Int(Date().timeIntervalSince(t0))) s")

        try await tap(display)
        #expect(await wait("the breakpoint", seconds: 120) { m.debug.isPaused && !m.debug.variables.isEmpty && m.activityText == "Paused TapCounter" })
        #expect(m.debug.frames.first?.name.contains("buttonTapped") == true)
        #expect(m.debug.frames.first?.file?.hasSuffix("TapCounter.swift") == true && m.debug.frames.first?.line == Self.handlerLine)
        let names = Set(m.debug.variables.map(\.name))
        #expect(names.isSuperset(of: ["sender", "self"]), "variables: \(m.debug.variables.map { "\($0.name)=\($0.value)" })")
        #expect(m.debug.variables.first { $0.name == "sender" }?.type == "UIButton")
        print("e2e: stopped: frames \(m.debug.frames.prefix(4).map(\.name)), variables \(m.debug.variables.map { "\($0.name): \($0.type ?? "") = \($0.value)" })")

        let stops = m.session.stopCount
        m.perform(.stepOver)
        #expect(await wait("the step", seconds: 60) { m.session.stopCount > stops && m.debug.isPaused && !m.debug.variables.isEmpty })
        #expect(value(m, "step") == "1", "step = \(value(m, "step") ?? "nil")")

        m.perform(.pauseOrContinue)
        #expect(await wait("running again", seconds: 60) { !m.debug.isPaused && m.activityText.hasPrefix("Running TapCounter") })
        try await tap(display)
        #expect(await wait("the second stop", seconds: 120) { m.debug.isPaused && !m.debug.variables.isEmpty })
        let again = m.session.stopCount
        m.perform(.stepOver)
        #expect(await wait("the second step", seconds: 60) { m.session.stopCount > again && m.debug.isPaused && !m.debug.variables.isEmpty })
        #expect(value(m, "step") == "2", "step = \(value(m, "step") ?? "nil")")
        m.perform(.pauseOrContinue)
        #expect(await wait("running", seconds: 60) { !m.debug.isPaused })

        m.stop()
        #expect(await wait("the detach", seconds: 60) { !m.session.isDebuggingSimulatorStub && !m.debug.isDebugging })
        print("e2e: done after \(Int(Date().timeIntervalSince(t0))) s")
    }
}
