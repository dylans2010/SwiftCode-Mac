import Foundation
import YcodeDarwinABI

public enum HostStreamSockets {
    static let diagnosticdPath = "/private/var/run/.sim_diagnosticd_socket"
    static let logDiagnosticd = flag("SWIFTCODE_SIM_DIAGNOSTICD_LOG")
    nonisolated(unsafe) static var diagnosticdEnabled =
        !flag("SWIFTCODE_DEBUG_NO_HOST_SOCKETS") && (flag("SWIFTCODE_SIM_DIAGNOSTICD_SOCKET") || logDiagnosticd)

    private static func flag(_ name: String) -> Bool {
        getenv(name).map { String(cString: $0) == "1" } ?? false
    }

    nonisolated(unsafe) static var connections = 0
    nonisolated(unsafe) static var bytesReceived = 0

    static func sink(for path: String, from user: DescriptorUser) -> ((ArraySlice<UInt8>) -> Void)? {
        guard diagnosticdEnabled, path == diagnosticdPath || path == "/var/run/.sim_diagnosticd_socket" else { return nil }
        connections += 1
        let pid = user.pid
        if logDiagnosticd {
            stderr("swiftcode-simd: host socket \(diagnosticdPath): connection \(connections) from pid \(pid)")
        }
        return { bytes in
            bytesReceived += bytes.count
            guard logDiagnosticd else { return }
            stderr("swiftcode-simd: host socket \(diagnosticdPath) from pid \(pid): \(bytes.count) bytes: "
                + printableStrings(bytes).joined(separator: " | "))
        }
    }

    static let dnsServicePaths: Set<String> = ["/var/run/mDNSResponder", "/private/var/run/mDNSResponder"]

    static func endpoint(for path: String) -> ((UnixSocket, KernelLock, DescriptorUser) -> HostSocketEndpoint)? {
        if let server = channelServer(for: path) {
            return { host, lock, user in HostChannelConnection(host: host, lock: lock, pid: user.pid, server: server) }
        }
        guard !InetSocketPolicy.disabled, dnsServicePaths.contains(path) else { return nil }
        return { host, lock, user in DNSServiceConnection(host: host, lock: lock, pid: user.pid) }
    }

    nonisolated(unsafe) private static var channelServers: [String: HostChannelServer] = [:]
    private static let channelServersLock = NSLock()

    static func channelServer(for path: String) -> HostChannelServer? {
        channelServersLock.withLock { channelServers[path] }
    }

    public static func serve(paths: [String], with server: HostChannelServer) {
        channelServersLock.withLock { for p in paths { channelServers[p] = server } }
    }

    public static func stopServing(paths: [String]) {
        channelServersLock.withLock { for p in paths { channelServers[p] = nil } }
    }

    static func printableStrings(_ bytes: ArraySlice<UInt8>) -> [String] {
        var out: [String] = []
        var run: [UInt8] = []
        for b in bytes + [0] {
            if b >= 0x20 && b < 0x7F {
                run.append(b)
                continue
            }
            if run.count >= 3 { out.append(String(decoding: run, as: UTF8.self)) }
            run = []
        }
        return out
    }

    private static func stderr(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

public protocol HostChannelServer: AnyObject, Sendable {
    func channelOpened(_ connection: HostChannelConnection)
    func channel(_ connection: HostChannelConnection, received bytes: [UInt8])
    func channelClosed(_ connection: HostChannelConnection)
}

public final class HostChannelConnection: HostSocketEndpoint, @unchecked Sendable {
    private weak var host: UnixSocket?
    private let lock: KernelLock
    public let pid: Int32
    private let server: HostChannelServer
    private let queue: DispatchQueue
    private var isClosed = false

    init(host: UnixSocket, lock: KernelLock, pid: Int32, server: HostChannelServer) {
        self.host = host
        self.lock = lock
        self.pid = pid
        self.server = server
        queue = DispatchQueue(label: "swiftcode.host-channel.\(pid)")
        queue.async { [self] in server.channelOpened(self) }
    }

    func received(_ bytes: ArraySlice<UInt8>, rights: [DarwinOpenFile]?) {
        let copy = Array(bytes)
        queue.async { [self] in server.channel(self, received: copy) }
    }

    func disconnected() {
        isClosed = true
        queue.async { [self] in server.channelClosed(self) }
    }

    @discardableResult
    public func send(_ bytes: [UInt8]) -> Bool {
        lock.withLock {
            guard !isClosed, let host, let peer = host.peer, !peer.closed else { return false }
            peer.appendStream(bytes[...], rights: nil)
            host.changedWithPeer()
            return true
        }
    }

    public func close() {
        lock.withLock {
            guard !isClosed else { return }
            isClosed = true
            host?.disconnectStream()
        }
    }
}
