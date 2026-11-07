import Foundation
import YcodeDebug

extension WorkspaceSession {
    public enum StubAttachResult: Equatable, Sendable {
        case attached
        case cancelled
        case failed(String)
    }

    @discardableResult
    public func attachToSimulatorStub(socketPath: String, app appURL: URL, device: String, adapter: DAPTransport? = nil,
                                      waitSeconds: Double = 60, waitForLaunch: (() async -> Bool)? = nil,
                                      cancelled: @escaping @MainActor () -> Bool = { false }) async -> StubAttachResult {
        guard let app = AppBundle(url: appURL) else { return .failed("\(appURL.lastPathComponent) has no Info.plist") }
        beginDebugSession(product: app.executable)
        runningDeviceName = device
        if let waitForLaunch {
            setActivity(.running(RunActivityText.launching(app.executable)))
            let launched = await waitForLaunch()
            guard launched, !cancelled() else {
                if !cancelled() { appendConsole("SwiftCode: \(app.executable) did not launch on \(device); the debugger was not attached.\n", kind: .debugger) }
                finishStubAttach(app: app.executable, device: device)
                return cancelled() ? .cancelled : .failed("not launched")
            }
        }
        setActivity(.running(RunActivityText.configuringDebugger))
        var ready = false
        for _ in 0..<max(1, Int(waitSeconds * 10)) where !cancelled() {
            if await Task.detached(operation: { StubForward.unixSocketAccepts(socketPath) }).value { ready = true; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard !cancelled() else { finishStubAttach(app: app.executable, device: device); return .cancelled }
        guard ready else {
            appendConsole("SwiftCode: the debugger could not reach the app on \(device) (no debug stub at \(socketPath))\n", kind: .debugger)
            finishStubAttach(app: app.executable, device: device)
            return .failed("no debug stub")
        }
        let forward: StubForward
        do { forward = try StubForward(unixSocket: socketPath) } catch {
            appendConsole("SwiftCode: the debugger's forward did not start: \(error)\n", kind: .debugger)
            finishStubAttach(app: app.executable, device: device)
            return .failed("\(error)")
        }
        let transport: DAPTransport
        if let adapter { transport = adapter } else {
            guard let path = await Task.detached(operation: { LLDBDAP.locate() }).value else {
                appendConsole("SwiftCode: lldb-dap was not found.\n")
                forward.close()
                finishStubAttach(app: app.executable, device: device)
                return .failed("lldb-dap was not found")
            }
            transport = ProcessTransport(executable: path)
        }
        do {
            let client = try DAPClient(transport: transport)
            debugClient = client
            adapterInitialized = false
            stubForward = forward
            Task { [weak self] in
                for await e in client.events { await self?.handle(e) }
                forward.close()
                if self?.stubForward === forward { self?.stubForward = nil }
                self?.sessionEnded()
            }
            try await client.initialize()
            attachingSimulatorApp = true
            defer { attachingSimulatorApp = false }
            let dir = app.executableURL.deletingLastPathComponent().path
            try await client.attachRemote(port: forward.port, program: app.executableURL.path, threadFormat: DebugThread.format,
                                          preRunCommands: RemoteSimulator.debuggerSettings(appDirectory: dir) + Self.hostSignalCommands)
            for _ in 0..<1200 where stoppedThread == nil && debugClient === client && !cancelled() {
                try? await Task.sleep(for: .milliseconds(100))
            }
            attachingSimulatorApp = false
            if stoppedThread != nil, debugClient === client { await continueOrPause() }
        } catch {
            appendConsole("SwiftCode: attach failed: \(error)\n")
            forward.close()
            if let c = debugClient { c.close() }
            return .failed("\(error)")
        }
        if debugClient != nil, case .running = activity, stoppedThread == nil {
            setActivity(.running(RunActivityText.running(app.executable, on: device)))
        }
        return .attached
    }

    public var isDebuggingSimulatorStub: Bool { stubForward != nil && debugClient != nil }

    public func detachFromSimulatorStub() {
        stubForward?.close()
        stubForward = nil
        guard let c = debugClient else { return }
        Task {
            try? await c.disconnect(terminate: false)
            c.close()
        }
    }

    nonisolated static var hostSignalCommands: [String] {
        #if os(Linux)
        ["process handle -s true -p false -n true SIGCHLD", "process handle -s true -p true -n true SIGUSR1"]
        #else
        []
        #endif
    }

    private func finishStubAttach(app: String, device: String) {
        endDebugSession()
        setActivity(.finished(RunActivityText.finished(app, on: device)))
    }
}
