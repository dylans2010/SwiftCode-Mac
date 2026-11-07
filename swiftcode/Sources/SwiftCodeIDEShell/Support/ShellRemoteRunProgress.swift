import Foundation
import SwiftCodeBuild
import SwiftCodeIDECore
import SwiftCodeSimLink

public enum RemoteRunPhase: Equatable, Sendable {
    case building
    case launching
    case running
    case failed(String)
    case ended
}

extension ShellRemoteRun {
    public static func newDeviceDestination(host: String, deviceTypes: [String], runtime: String?) -> Destination? {
        let preferred = ["iphone-18-pro"] + SwiftCodeSimulatorDeviceType.all.map(\.id)
        guard let id = preferred.first(where: deviceTypes.contains) else { return nil }
        let name = SwiftCodeSimulatorDeviceType.named(id)?.name ?? id
        let info = LinkDeviceInfo(name: deviceDirectoryName(name), deviceType: id, runtime: runtime ?? "", state: "shutdown")
        var d = destination(host: host, device: info)
        d.name = "\(name) (\(host))"
        return d
    }

    public static func deviceDirectoryName(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "-" })
    }

    public static func noDevicesMessage(host: String) -> String {
        "The simulator host \(host) has no devices and offers no iPhone type. Check its runtime with Window ▸ Downloads."
    }

    static func ensureDevice(_ c: LinkClient.Control, device: String, type: String?, host: String,
                             output: @Sendable (String) -> Void) throws -> Bool {
        let list = try c.request(LinkRequest(op: "devices"))
        if let d = list.devices?.first(where: { $0.name == device }) {
            if d.state == "running" || d.state == "booting" {
                output(restartLine(device: device))
            }
            return false
        }
        output("Creating \(device) on \(host)…\n")
        let r = try c.request(LinkRequest(op: "create", device: device, deviceType: type ?? "iphone-18-pro"))
        guard r.ok else { throw Failure(description: "creating \(device) on \(host) failed: \(r.error ?? "no reason given")") }
        output("Created \(device). Its first boot sets the device up and takes a few minutes; later runs start in seconds.\n")
        return true
    }

    public static func restartLine(device: String) -> String { "\(device) is running; saving it and starting it again with the app…\n" }

    public static func bootingLine(device: String, seconds: Int) -> String { "Booting \(device)… \(seconds) s\n" }

    public static func bootedLine(device: String, seconds: Int) -> String { "\(device) is running (\(seconds) s).\n" }

    public static func displayUpLine(device: String, seconds: Int) -> String {
        "\(device)'s display is up (\(seconds) s); waiting for the app to open.\n"
    }

    public static func appOpenedLine(app: String, device: String, seconds: Int) -> String { "\(app) is open on \(device) (\(seconds) s).\n" }

    public static func stoppedWhileBootingMessage(device: String, host: String, log: [String]) -> String {
        var s = "\(device) stopped on \(host) before its display came up."
        let tail = log.suffix(8).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !tail.isEmpty { s += " The host's log for it ends with:\n" + tail.map { "  " + $0 }.joined(separator: "\n") }
        return s
    }

    public enum AppLaunchState: Equatable { case waiting, opened, failed(String) }

    public static func appLaunchState(log: [String]) -> AppLaunchState {
        for line in log.reversed() {
            if line.contains("app launch: open request took") || line.contains("app launch: launched ") { return .opened }
            if line.contains("app install: failed") || line.contains("app launch: failed") { return .failed(line) }
        }
        return .waiting
    }

    static func watchBoot(host: LinkHost, device: String, app: String? = nil, client: LinkClient, every: Int = 10, limit: TimeInterval = 1800,
                          output: @escaping @Sendable (String) -> Void, phase: @escaping @Sendable (RemoteRunPhase) -> Void) {
        Thread.detachNewThread {
            let start = Date()
            var lastLine = 0
            var sawBooting = false
            var displayUp = false
            guard let c = try? client.control(host) else { return }
            defer { c.close() }
            while Date().timeIntervalSince(start) < limit {
                Thread.sleep(forTimeInterval: 1)
                let s = Int(Date().timeIntervalSince(start))
                guard let r = try? c.request(LinkRequest(op: "devices")), let d = r.devices?.first(where: { $0.name == device }) else { continue }
                if d.state == "running" {
                    guard let app else {
                        output(bootedLine(device: device, seconds: s))
                        phase(.running)
                        return
                    }
                    if !displayUp {
                        displayUp = true
                        output(displayUpLine(device: device, seconds: s))
                    }
                    let log = (try? c.request(LinkRequest(op: "log", device: device, lines: 200)))?.log ?? []
                    switch appLaunchState(log: log) {
                    case .opened:
                        output(appOpenedLine(app: app, device: device, seconds: s))
                        phase(.running)
                        return
                    case .failed(let line):
                        phase(.failed("\(app) did not open on \(device): \(line)"))
                        return
                    case .waiting:
                        if s - lastLine >= every {
                            lastLine = s
                            output(bootingLine(device: device, seconds: s))
                        }
                    }
                } else if d.state == "booting" {
                    sawBooting = true
                    if s - lastLine >= every {
                        lastLine = s
                        output(bootingLine(device: device, seconds: s))
                    }
                } else if d.state == "shutdown", sawBooting || displayUp || s > 5 {
                    let log = (try? c.request(LinkRequest(op: "log", device: device, lines: 40)))?.log ?? []
                    phase(.failed(stoppedWhileBootingMessage(device: device, host: host.name, log: log)))
                    return
                }
            }
        }
    }
}

extension WorkspaceShellModel {
    func remoteRunPhase(_ p: RemoteRunPhase, product: String, device: String) {
        switch p {
        case .building: session.noteToolActivity(.building(WorkspaceSession.BuildActivityText.accepted))
        case .launching: session.noteToolActivity(.running(WorkspaceSession.RunActivityText.launching(product)))
        case .running: session.noteToolActivity(.running(WorkspaceSession.RunActivityText.running(product, on: device)))
        case .failed(let why):
            if !why.isEmpty { session.appendConsole(why + "\n", kind: .debugger) }
            if case .building = session.activity {
                session.noteToolActivity(.finished("Build Failed"))
            } else {
                session.noteToolActivity(.finished(WorkspaceSession.RunActivityText.finished(product, on: device)))
            }
        case .ended:
            guard session.isBusy else { return }
            if case .building = session.activity {
                session.noteToolActivity(.finished("Build Cancelled"))
            } else {
                session.noteToolActivity(.finished(WorkspaceSession.RunActivityText.finished(product, on: device)))
            }
        }
    }
}

public final class RemoteRunCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }

    func started(_ p: Process) {
        let stop = lock.withLock { () -> Bool in
            process = p
            return cancelled
        }
        if stop { Self.end(p.processIdentifier) }
    }

    public func cancel() {
        let p = lock.withLock { () -> Process? in
            cancelled = true
            return process
        }
        if let p { Self.end(p.processIdentifier) }
    }

    static func end(_ pid: Int32) {
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }
    }
}

extension ShellRemoteRun {
    public static func defaultDestination(_ groups: [DestinationGroup], model: WorkspaceModel) -> Destination? {
        guard let proj = model.projects.keys.sorted().first.flatMap({ model.projects[$0] }) else { return nil }
        return defaultDestination(groups, productPlatform: DestinationMenuModel.productPlatform(of: proj).platform)
    }

    public static func defaultDestination(_ groups: [DestinationGroup], productPlatform: String?) -> Destination? {
        guard productPlatform == "iOS" else { return nil }
        return groups.lazy.flatMap(\.destinations).first { target(of: $0).map { !$0.device.isEmpty } ?? false }
    }
}
