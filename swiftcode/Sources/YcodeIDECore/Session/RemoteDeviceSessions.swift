import Foundation
import YcodeSubprocess

@MainActor
public final class RemoteDeviceSessions {
    public static let shared = RemoteDeviceSessions()
    public static let didChange = Notification.Name("SwiftCodeRemoteDeviceSessionsDidChange")

    final class Entry {
        let remote: RemoteSimulator
        let process: StreamingProcess
        var pid: Int?
        var stopping = false
        var exited: [CheckedContinuation<Void, Never>] = []
        var done = false
        init(remote: RemoteSimulator, process: StreamingProcess) {
            self.remote = remote
            self.process = process
        }
    }

    private var entries: [String: Entry] = [:]
    private var quitObserver: NSObjectProtocol?

    func shutDownAllForQuit() {
        for e in entries.values where !e.done {
            if let pid = e.pid { _ = e.remote.signalRemote(pid, signal: "INT") } else { e.process.signal(SIGINT) }
        }
    }
    public var output: (String) -> Void = { _ in }

    public func isRunning(_ remote: RemoteSimulator) -> Bool { entries[remote.remoteDevicePath] != nil }
    public var runningDevicePaths: Set<String> { Set(entries.keys) }

    @discardableResult
    public func start(_ remote: RemoteSimulator) -> Bool {
        guard remote.settings.isConfigured, entries[remote.remoteDevicePath] == nil else { return false }
        if quitObserver == nil {
            quitObserver = NotificationCenter.default.addObserver(forName: IDEProcess.willTerminateNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { RemoteDeviceSessions.shared.shutDownAllForQuit() }
            }
        }
        let proc = StreamingProcess(executable: remote.settings.ssh, arguments: remote.sshArguments(remote.startCommand))
        let e = Entry(remote: remote, process: proc)
        entries[remote.remoteDevicePath] = e
        do {
            try proc.start(onLine: { [weak self, weak e] line in
                if let pid = RemoteSimulator.remotePID(line) { e?.pid = pid; return }
                self?.output(line)
            }, onExit: { [weak self, weak e] _ in
                guard let self, let e else { return }
                e.done = true
                if self.entries[e.remote.remoteDevicePath] === e { self.entries[e.remote.remoteDevicePath] = nil }
                e.exited.forEach { $0.resume() }
                e.exited = []
                NotificationCenter.default.post(name: Self.didChange, object: self)
            })
        } catch {
            entries[remote.remoteDevicePath] = nil
            return false
        }
        NotificationCenter.default.post(name: Self.didChange, object: self)
        return true
    }

    public func shutDown(_ remote: RemoteSimulator, force: Bool = false) async {
        guard let e = entries[remote.remoteDevicePath], !e.done else { return }
        e.stopping = true
        if let pid = e.pid {
            let status = await Task.detached { remote.signalRemote(pid, signal: force ? "KILL" : "INT") }.value
            if status != 0 { e.process.signal(SIGINT) }
        } else {
            e.process.signal(SIGINT)
        }
        let grace = remote.stopGrace
        Task { [weak e] in
            try? await Task.sleep(for: .seconds(grace))
            if let e, !e.done { e.process.signal(SIGINT) }
        }
        if !e.done { await withCheckedContinuation { e.exited.append($0) } }
    }

    public func shutDownAll() async {
        for e in entries.values { await shutDown(e.remote) }
    }
}
