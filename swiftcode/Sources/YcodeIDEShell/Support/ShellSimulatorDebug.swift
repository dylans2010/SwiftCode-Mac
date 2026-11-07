import Foundation
import YcodeBuild
import YcodeIDECore
import YcodeSimLink
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum ShellSimulatorDebug {
    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["SWIFTCODE_IDE_SIM_DEBUGGER"] != "0"
    }

    public static func isThisMachine(_ address: String, interfaceAddresses: Set<String>? = nil,
                                     hostName: String = ProcessInfo.processInfo.hostName) -> Bool {
        var a = address.lowercased()
        if a.hasPrefix("["), a.hasSuffix("]") { a = String(a.dropFirst().dropLast()) }
        if a == "localhost" || a.hasSuffix(".localhost") || a == "::1" || a.hasPrefix("127.") { return true }
        if !hostName.isEmpty, a == hostName.lowercased() || a.split(separator: ".").first.map(String.init) == hostName.lowercased() { return true }
        return (interfaceAddresses ?? localAddresses()).contains(a)
    }

    public static func localAddresses() -> Set<String> {
        var out: Set<String> = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return out }
        defer { freeifaddrs(list) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let i = p {
            defer { p = i.pointee.ifa_next }
            guard let sa = i.pointee.ifa_addr else { continue }
            let family = Int32(sa.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var name = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            if getnameinfo(sa, len, &name, socklen_t(name.count), nil, 0, NI_NUMERICHOST) == 0 {
                let text = String(cString: name).split(separator: "%").first.map(String.init) ?? ""
                if !text.isEmpty { out.insert(text.lowercased()) }
            }
        }
        return out
    }

    public static func wantsDebugger(host: LinkHost, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        isEnabled(environment: environment) && isThisMachine(host.host)
    }

    public static func launchedPID(_ line: String, bundleID: String?) -> Int? {
        guard let r = line.range(of: "ylaunch: launched ") else { return nil }
        let rest = line[r.upperBound...].split(separator: " ")
        guard rest.count >= 3, rest[1] == "pid", let pid = Int(rest[2]) else { return nil }
        if let bundleID, rest[0] != bundleID { return nil }
        return pid
    }

    public static func waitForLaunch(host: LinkHost, device: String, bundleID: String?, timeout: Double = 900, interval: Double = 1,
                                     cancelled: @escaping @Sendable () async -> Bool) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if await cancelled() { return false }
            let (lines, state): ([String], String?) = await Task.detached { () -> ([String], String?) in
                guard let c = try? LinkClient().control(host) else { return ([], nil) }
                defer { c.close() }
                let log = (try? c.request(LinkRequest(op: "log", device: device, lines: 400)))?.log ?? []
                let state = (try? c.request(LinkRequest(op: "devices")))?.devices?.first { $0.name == device }?.state
                return (log, state)
            }.value
            if lines.contains(where: { launchedPID($0, bundleID: bundleID) != nil }) { return true }
            if state == "shutdown", Date().timeIntervalSince(start) > 5 { return false }
            try? await Task.sleep(for: .seconds(interval))
        }
        return false
    }

    @MainActor
    public static func run(session: WorkspaceSession, scheme: String, destination: Destination, packageRoot: URL,
                           phase: @escaping @Sendable (RemoteRunPhase) -> Void = { _ in }, cancel: RemoteRunCancel = RemoteRunCancel(),
                           started: (Process) -> Void, isCurrent: @escaping @MainActor (Process) -> Bool) async throws {
        let out: @Sendable (String) -> Void = { text in Task { @MainActor in session.appendConsole(text, kind: .debugger) } }
        let s = try await ShellRemoteRun.start(project: session.model.url.path, scheme: scheme, destination: destination, packageRoot: packageRoot,
                                               debug: isEnabled(), output: out, phase: phase, cancel: cancel)
        started(s.viewer)
        guard let socket = s.debugSocket else {
            if isEnabled(), !isThisMachine(s.host.host) {
                out("The debugger attaches only to a simulator host on this computer; \(s.host.name) runs \(s.app.deletingPathExtension().lastPathComponent) without it.\n")
            }
            return
        }
        let viewer = s.viewer, host = s.host, device = s.device, bundleID = s.bundleID
        await session.attachToSimulatorStub(socketPath: socket, app: s.app, device: "\(device) (\(host.name))", waitForLaunch: {
            await waitForLaunch(host: host, device: device, bundleID: bundleID) { await MainActor.run { !isCurrent(viewer) } }
        }, cancelled: { !isCurrent(viewer) })
    }
}
