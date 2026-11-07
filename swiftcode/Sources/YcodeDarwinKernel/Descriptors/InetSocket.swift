import Foundation
import YcodeDarwinABI
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class InetSocket: KernelDescriptorObject, HostPolledObject {
    enum State: UInt8 {
        case idle = 0
        case connecting = 1
        case connected = 2
        case listening = 3
    }

    struct OptionKey: Hashable {
        var level: Int32
        var name: Int32
    }

    let domain: Int32
    let type: Int32
    let proto: Int32
    let lock: KernelLock
    let signals = ObjectSignals()
    let inode = DescriptorInodes.make()
    let creator: DescriptorUser
    var lastUser: DescriptorUser

    private(set) var hostFD: Int32
    var state: State = .idle
    var datagramConnected = false
    var bound = false
    var pendingError: Int32 = 0
    var isReset = false
    var shutRead = false
    var shutWrite = false
    var closed = false

    var noSigPipe = false
    var receiveTimeout: UInt64?
    var sendTimeout: UInt64?
    var localOptions: [OptionKey: [UInt8]] = [:]
    var appliedOptions: [(key: OptionKey, value: [UInt8])] = []
    var requestedSendBuffer: Int32?
    var requestedReceiveBuffer: Int32?
    var wants = ControlMessages.ReceiveWants()
    var boundInterface: UInt32 = 0
    var boundAddress: InetAddress?
    var backlog: Int32 = 0

    private var pollToken: UInt64?

    init(domain: Int32, type: Int32, proto: Int32, hostFD: Int32, lock: KernelLock, creator: DescriptorUser) {
        self.domain = domain
        self.type = type
        self.proto = proto
        self.hostFD = hostFD
        self.lock = lock
        self.creator = creator
        self.lastUser = creator
        if hostFD >= 0 { InetSocketStats.add(1) }
    }

    deinit {
        if hostFD >= 0 { closeHostSocket() }
    }

    var isStream: Bool { type == InetABI.sockStream }
    var fileType: UInt16 { DarwinStat.S_IFSOCK }

    static func makeHost(domain: Int32, type: Int32, proto: Int32) throws -> Int32 {
        let family = domain == InetABI.afInet ? HostNet.afInet : HostNet.afInet6
        let fd = HostSocketCalls.socket(family: family, type: type, proto: proto)
        guard fd >= 0 else { throw SocketErrno.last() }
        if domain == InetABI.afInet6 {
            #if canImport(Glibc)
            _ = HostSocketCalls.setInt(fd, level: InetABI.ipprotoIPv6, name: HostNet.ipv6V6Only, 0)
            #endif
        }
        return fd
    }

    func lastReferenceClosed() {
        lock.withLock {
            closed = true
            closeHostSocket()
            signals.fire()
        }
    }

    func closeHostSocket() {
        let fd = hostFD
        guard fd >= 0 else { return }
        hostFD = -1
        if let t = pollToken { HostSocketPoller.shared.remove(fd: fd, token: t) }
        pollToken = nil
        InetSocketStats.add(-1)
        if let l = localOptions[OptionKey(level: InetABI.solSocket, name: InetABI.soLinger)] ?? lingerOption,
           l.readLE(Int32.self, at: 0) != 0, l.readLE(Int32.self, at: 4) > 0 {
            DispatchQueue.global().async { _ = close(fd) }
        } else {
            _ = close(fd)
        }
    }

    private var lingerOption: [UInt8]? {
        appliedOptions.last { $0.key.level == InetABI.solSocket
            && ($0.key.name == InetABI.soLinger || $0.key.name == InetABI.soLingerSec) }?.value
    }

    func replaceHost(_ fd: Int32) {
        guard hostFD < 0, fd >= 0 else { return }
        hostFD = fd
        pollToken = nil
        InetSocketStats.add(1)
    }

    func descriptorStat() -> DarwinStat {
        var mode = DarwinStat.S_IFSOCK
        if !shutRead { mode |= 0o444 }
        if !shutWrite { mode |= 0o222 }
        let n = hostFD >= 0 ? HostSocketCalls.bytesReadable(hostFD) : 0
        return DarwinStat(mode: mode, nlink: 0, ino: inode, uid: creator.uid, gid: creator.gid,
                          size: Int64(n), blksize: 131_072)
    }

    func hostDescriptorChanged() {
        lock.withLock {
            guard !closed else { return }
            signals.fire()
        }
    }

    func arm() {
        guard pollToken == nil, hostFD >= 0 else { return }
        pollToken = HostSocketPoller.shared.add(fd: hostFD, object: self)
    }

    func wait(_ kernel: DarwinKernel, deadline: UInt64?) throws -> Bool {
        arm()
        return try kernel.waitOnObject(signals, deadline: deadline)
    }

    func addReadinessObserver(_ observer: @escaping () -> Void) -> Int {
        arm()
        return signals.addObserver(observer)
    }

    func removeReadinessObserver(_ token: Int) { signals.removeObserver(token) }

    func refreshConnecting() {
        guard state == .connecting, hostFD >= 0 else { return }
        let r = HostSocketCalls.revents(hostFD)
        guard r & Int16(POLLOUT | POLLERR | POLLHUP) != 0 else { return }
        let e = HostSocketCalls.intOption(hostFD, level: HostNet.solSocket, name: Int32(SO_ERROR)) ?? 0
        if e == 0 {
            state = .connected
            bound = true
        } else {
            pendingError = SocketErrno.fromHost(e)
            state = .idle
        }
    }

    func takeError() throws {
        if pendingError != 0 {
            let e = pendingError
            pendingError = 0
            throw DarwinErrnoError(e)
        }
    }

    func keepsLocally(level: Int32, name: Int32) -> Bool {
        switch (level, name) {
        case (InetABI.ipprotoIP, InetABI.ipRecvDstAddr), (InetABI.ipprotoIP, InetABI.ipPktInfo),
             (InetABI.ipprotoIP, InetABI.ipRecvIF), (InetABI.ipprotoIP, InetABI.ipBoundIF),
             (InetABI.ipprotoIPv6, InetABI.ipv6BoundIF), (InetABI.ipprotoIP, InetABI.ipMulticastIfIndex):
            return true
        default:
            return false
        }
    }

    func applyHostOption(level: Int32, name: Int32, value: [UInt8]) throws -> Bool {
        guard hostFD >= 0 else { return false }
        func setHost(_ l: Int32, _ n: Int32, _ v: [UInt8]) -> Bool {
            HostSocketCalls.setOption(hostFD, level: l, name: n, value: v) == 0
        }
        switch (level, name) {
        case (InetABI.ipprotoIP, InetABI.ipRecvDstAddr), (InetABI.ipprotoIP, InetABI.ipPktInfo),
             (InetABI.ipprotoIP, InetABI.ipRecvIF):
            #if canImport(Glibc)
            let any: Int32 = wants.dstAddr || wants.pktInfo || wants.recvIF ? 1 : 0
            _ = HostSocketCalls.setInt(hostFD, level: InetABI.ipprotoIP, name: HostNet.ipPktInfo, any)
            #else
            _ = setHost(level, name, value)
            #endif
            return true
        case (InetABI.ipprotoIP, InetABI.ipBoundIF), (InetABI.ipprotoIPv6, InetABI.ipv6BoundIF):
            #if canImport(Glibc)
            _ = HostSocketCalls.setInt(hostFD, level: HostNet.solSocket, name: HostNet.soBindToIfIndex,
                                       Int32(bitPattern: NetworkInterfaces.hostIndex(boundInterface)))
            #endif
            return true
        case (InetABI.ipprotoIP, InetABI.ipMulticastIfIndex):
            guard value.count >= 4 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            #if canImport(Glibc)
            var mreqn = [UInt8](repeating: 0, count: 8)
            mreqn.appendLE(NetworkInterfaces.hostIndex(value.readLE(UInt32.self, at: 0)))
            guard setHost(InetABI.ipprotoIP, HostNet.ipMulticastIF, mreqn) else { throw SocketErrno.last() }
            #else
            guard setHost(level, name, value) else { throw SocketErrno.last() }
            #endif
            return true
        default:
            break
        }
        switch SocketOptions.route(level: level, name: name) {
        case .local:
            return false
        case let .host(hl, hn, kind):
            let v = try SocketOptions.hostValue(value, kind: kind, hostIndex: NetworkInterfaces.hostIndex)
            if setHost(hl, hn, v) { return true }
            let e = errno
            if e == ENOPROTOOPT || e == EOPNOTSUPP { return false }
            throw DarwinErrnoError(SocketErrno.fromHost(e))
        }
    }

    func readReadiness() -> (ready: Bool, data: Int64, eof: Bool) {
        if isReset || closed || hostFD < 0 { return (true, 0, true) }
        if pendingError != 0 { return (true, 0, false) }
        switch state {
        case .listening:
            let r = HostSocketCalls.revents(hostFD)
            let ready = r & Int16(POLLIN) != 0
            return (ready, ready ? 1 : 0, false)
        case .connecting:
            refreshConnecting()
            if state == .connecting { return (false, 0, false) }
            if pendingError != 0 { return (true, 0, false) }
        case .idle where isStream:
            return (shutRead, 0, shutRead)
        default:
            break
        }
        let r = HostSocketCalls.revents(hostFD)
        let n = HostSocketCalls.bytesReadable(hostFD)
        let error = r & Int16(POLLERR) != 0
        if isStream {
            let eof = shutRead || r & (Int16(POLLHUP) | HostSocketCalls.rdHup) != 0 || (r & Int16(POLLIN) != 0 && n == 0)
            let lowat = Int(localOptions[OptionKey(level: InetABI.solSocket, name: InetABI.soRcvLowat)]?
                .readLE(Int32.self, at: 0) ?? 1)
            return (n >= max(1, lowat) || eof || error, Int64(n), eof)
        }
        return (r & Int16(POLLIN) != 0 || error || shutRead, Int64(n), shutRead)
    }

    func writeReadiness() -> (ready: Bool, data: Int64, eof: Bool) {
        if isReset || closed || hostFD < 0 || shutWrite { return (true, 0, true) }
        if pendingError != 0 { return (true, 0, false) }
        switch state {
        case .listening: return (false, 0, false)
        case .connecting:
            refreshConnecting()
            if state == .connecting { return (false, 0, false) }
            if pendingError != 0 { return (true, 0, false) }
        case .idle where isStream:
            return (false, 0, false)
        default:
            break
        }
        let r = HostSocketCalls.revents(hostFD)
        let hup = r & Int16(POLLHUP) != 0
        let space = max(0, Int(sendBufferSize) - HostSocketCalls.bytesUnsent(hostFD))
        return (r & Int16(POLLOUT) != 0 || hup || r & Int16(POLLERR) != 0, Int64(space), hup)
    }

    var sendBufferSize: Int32 {
        if let r = requestedSendBuffer { return r }
        let v = hostFD >= 0 ? HostSocketCalls.intOption(hostFD, level: HostNet.solSocket, name: Int32(SO_SNDBUF)) ?? 0 : 0
        return HostNet.isLinux ? v / 2 : v
    }

    var receiveBufferSize: Int32 {
        if let r = requestedReceiveBuffer { return r }
        let v = hostFD >= 0 ? HostSocketCalls.intOption(hostFD, level: HostNet.solSocket, name: Int32(SO_RCVBUF)) ?? 0 : 0
        return HostNet.isLinux ? v / 2 : v
    }
}

enum InetSocketStats {
    private static let mutex = NSLock()
    nonisolated(unsafe) private static var openCount = 0
    nonisolated(unsafe) private(set) static var created = 0

    static func add(_ n: Int) {
        mutex.lock()
        openCount += n
        if n > 0 { created += n }
        mutex.unlock()
    }

    static var open: Int {
        mutex.lock()
        defer { mutex.unlock() }
        return openCount
    }
}
