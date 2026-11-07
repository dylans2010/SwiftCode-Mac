import Foundation
import SwiftCodeDarwinABI
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

enum InetSnapshotTag {
    static let domain: UInt16 = 1, type: UInt16 = 2, proto: UInt16 = 3, creator: UInt16 = 4, lastUser: UInt16 = 5
    static let state: UInt16 = 6, flags: UInt16 = 7, pendingError: UInt16 = 8, receiveTimeout: UInt16 = 9
    static let sendTimeout: UInt16 = 10, localOptions: UInt16 = 11, appliedOptions: UInt16 = 12
    static let sendBuffer: UInt16 = 13, receiveBuffer: UInt16 = 14, boundInterface: UInt16 = 15
    static let boundAddress: UInt16 = 16, peerAddress: UInt16 = 17, backlog: UInt16 = 18
}

extension InetSocket {
    func snapshotFields(user: (DescriptorUser) -> SnapshotFields) -> SnapshotFields {
        typealias T = InetSnapshotTag
        var f = SnapshotFields()
        f.i64(T.domain, Int64(domain))
        f.i64(T.type, Int64(type))
        f.i64(T.proto, Int64(proto))
        f.nested(T.creator, user(creator))
        f.nested(T.lastUser, user(lastUser))
        refreshConnecting()
        f.u64(T.state, UInt64(state.rawValue))
        var flags: UInt64 = 0
        for (bit, on) in [datagramConnected, bound, isReset, shutRead, shutWrite, noSigPipe,
                          wants.dstAddr, wants.pktInfo, wants.recvIF].enumerated() where on {
            flags |= 1 << UInt64(bit)
        }
        f.u64(T.flags, flags)
        f.i64(T.pendingError, Int64(pendingError))
        if let t = receiveTimeout { f.u64(T.receiveTimeout, t) }
        if let t = sendTimeout { f.u64(T.sendTimeout, t) }
        func option(_ k: OptionKey, _ v: [UInt8]) -> SnapshotFields {
            var g = SnapshotFields()
            g.i64(1, Int64(k.level))
            g.i64(2, Int64(k.name))
            g.bytes(3, v)
            return g
        }
        f.list(T.localOptions, localOptions.sorted { ($0.key.level, $0.key.name) < ($1.key.level, $1.key.name) }
            .map { option($0.key, $0.value) })
        f.list(T.appliedOptions, appliedOptions.map { option($0.key, $0.value) })
        if let v = requestedSendBuffer { f.i64(T.sendBuffer, Int64(v)) }
        if let v = requestedReceiveBuffer { f.i64(T.receiveBuffer, Int64(v)) }
        f.u64(T.boundInterface, UInt64(boundInterface))
        if let a = boundAddress { f.bytes(T.boundAddress, a.darwinBytes) }
        if datagramConnected, hostFD >= 0, let raw = HostSocketCalls.name(hostFD, peer: true),
           let peer = InetAddress.fromHost(raw, guestScope: NetworkInterfaces.guestIndex) {
            f.bytes(T.peerAddress, peer.darwinBytes)
        }
        f.i64(T.backlog, Int64(backlog))
        return f
    }

    static func restored(_ r: SnapshotFieldReader, lock: KernelLock,
                         user: (SnapshotFieldReader?) -> DescriptorUser) -> (InetSocket, String?) {
        typealias T = InetSnapshotTag
        let domain = r.i32(T.domain), type = r.i32(T.type), proto = r.i32(T.proto)
        let flags = r.u64(T.flags)
        func bit(_ b: Int) -> Bool { flags & (1 << UInt64(b)) != 0 }
        let state = State(rawValue: UInt8(truncatingIfNeeded: r.u64(T.state))) ?? .idle
        let s = InetSocket(domain: domain, type: type, proto: proto, hostFD: -1, lock: lock, creator: user(r.nested(T.creator)))
        s.lastUser = user(r.nested(T.lastUser))
        s.datagramConnected = bit(0)
        s.bound = bit(1)
        s.isReset = bit(2)
        s.shutRead = bit(3)
        s.shutWrite = bit(4)
        s.noSigPipe = bit(5)
        s.wants = ControlMessages.ReceiveWants(dstAddr: bit(6), pktInfo: bit(7), recvIF: bit(8))
        s.pendingError = r.i32(T.pendingError)
        s.receiveTimeout = r.optionalU64(T.receiveTimeout)
        s.sendTimeout = r.optionalU64(T.sendTimeout)
        for g in r.list(T.localOptions) { s.localOptions[OptionKey(level: g.i32(1), name: g.i32(2))] = g.bytes(3) }
        s.appliedOptions = r.list(T.appliedOptions).map { (OptionKey(level: $0.i32(1), name: $0.i32(2)), $0.bytes(3)) }
        s.requestedSendBuffer = r.has(T.sendBuffer) ? r.i32(T.sendBuffer) : nil
        s.requestedReceiveBuffer = r.has(T.receiveBuffer) ? r.i32(T.receiveBuffer) : nil
        s.boundInterface = r.u32(T.boundInterface)
        s.boundAddress = r.has(T.boundAddress) ? try? InetAddress.fromDarwin(r.bytes(T.boundAddress), domain: domain) : nil
        s.backlog = r.i32(T.backlog)
        s.state = state

        func reset(_ why: String?) -> (InetSocket, String?) {
            s.isReset = true
            s.state = .idle
            if s.pendingError == 0 { s.pendingError = DarwinErrnoCode.ECONNRESET }
            return (s, why)
        }
        if s.isReset { return (s, nil) }
        if type == InetABI.sockStream, state == .connected || state == .connecting { return reset(nil) }
        guard let fd = try? makeHost(domain: domain, type: type, proto: proto) else {
            return reset("IP socket: no host socket at restore (errno \(errno))")
        }
        s.replaceHost(fd)
        for (k, v) in s.appliedOptions { _ = try? s.applyHostOption(level: k.level, name: k.name, value: v) }
        if s.bound, let a = s.boundAddress {
            let bytes = a.hostBytes(hostScope: NetworkInterfaces.hostIndex(a.scope))
            if HostSocketCalls.withAddress(bytes, { bind(fd, $0, $1) }) != 0 {
                let e = errno
                s.closeHostForRestore()
                return reset("IP socket \(a): cannot bind again at restore (errno \(e)); reset")
            }
        }
        if state == .listening, listen(fd, max(1, s.backlog)) != 0 {
            let e = errno
            s.closeHostForRestore()
            return reset("IP socket: cannot listen again at restore (errno \(e)); reset")
        }
        if s.datagramConnected, r.has(T.peerAddress),
           let peer = try? InetAddress.fromDarwin(r.bytes(T.peerAddress), domain: domain) {
            let bytes = peer.hostBytes(hostScope: NetworkInterfaces.hostIndex(peer.scope))
            _ = HostSocketCalls.withAddress(bytes) { connect(fd, $0, $1) }
        }
        return (s, nil)
    }

    func closeHostForRestore() {
        lock.withLock { closeHostSocket() }
    }
}
