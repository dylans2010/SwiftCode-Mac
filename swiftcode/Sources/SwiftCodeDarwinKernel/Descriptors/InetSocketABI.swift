import Foundation
import SwiftCodeDarwinABI
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

enum InetABI {
    static let afInet: Int32 = 2, afInet6: Int32 = 30, afLink: Int32 = 18, afRoute: Int32 = 17, afSystem: Int32 = 32
    static let sockStream: Int32 = 1, sockDgram: Int32 = 2, sockRaw: Int32 = 3
    static let ipprotoIP: Int32 = 0, ipprotoICMP: Int32 = 1, ipprotoTCP: Int32 = 6, ipprotoUDP: Int32 = 17,
               ipprotoIPv6: Int32 = 41, ipprotoICMPv6: Int32 = 58
    static let solSocket: Int32 = 0xFFFF

    static let soDebug: Int32 = 0x1, soAcceptConn: Int32 = 0x2, soReuseAddr: Int32 = 0x4, soKeepAlive: Int32 = 0x8,
               soDontRoute: Int32 = 0x10, soBroadcast: Int32 = 0x20, soUseLoopback: Int32 = 0x40, soLinger: Int32 = 0x80,
               soOOBInline: Int32 = 0x100, soReusePort: Int32 = 0x200, soTimestamp: Int32 = 0x400,
               soTimestampMonotonic: Int32 = 0x800, soSndBuf: Int32 = 0x1001, soRcvBuf: Int32 = 0x1002,
               soSndLowat: Int32 = 0x1003, soRcvLowat: Int32 = 0x1004, soSndTimeo: Int32 = 0x1005,
               soRcvTimeo: Int32 = 0x1006, soError: Int32 = 0x1007, soType: Int32 = 0x1008, soNRead: Int32 = 0x1020,
               soNoSigPipe: Int32 = 0x1022, soNWrite: Int32 = 0x1024, soLingerSec: Int32 = 0x1080
    static let scmRights: Int32 = 1, scmTimestamp: Int32 = 2, scmTimestampMonotonic: Int32 = 4

    static let ipOptions: Int32 = 1, ipHdrIncl: Int32 = 2, ipTOS: Int32 = 3, ipTTL: Int32 = 4, ipRecvOpts: Int32 = 5,
               ipRecvRetOpts: Int32 = 6, ipRecvDstAddr: Int32 = 7, ipRetOpts: Int32 = 8, ipMulticastIF: Int32 = 9,
               ipMulticastTTL: Int32 = 10, ipMulticastLoop: Int32 = 11, ipAddMembership: Int32 = 12,
               ipDropMembership: Int32 = 13, ipPortRange: Int32 = 19, ipRecvIF: Int32 = 20, ipStripHdr: Int32 = 23,
               ipRecvTTL: Int32 = 24, ipBoundIF: Int32 = 25, ipPktInfo: Int32 = 26, ipRecvTOS: Int32 = 27,
               ipDontFrag: Int32 = 28, ipMulticastIfIndex: Int32 = 66, ipAddSourceMembership: Int32 = 70,
               ipDropSourceMembership: Int32 = 71, ipBlockSource: Int32 = 72, ipUnblockSource: Int32 = 73

    static let ipv6UnicastHops: Int32 = 4, ipv6MulticastIF: Int32 = 9, ipv6MulticastHops: Int32 = 10,
               ipv6MulticastLoop: Int32 = 11, ipv6JoinGroup: Int32 = 12, ipv6LeaveGroup: Int32 = 13,
               ipv6PortRange: Int32 = 14, ipv6Checksum: Int32 = 26, ipv6V6Only: Int32 = 27,
               ipv6RecvTClass: Int32 = 35, ipv6TClass: Int32 = 36, ipv6RecvHopLimit: Int32 = 37,
               ipv6UseMinMTU: Int32 = 42, ipv6RecvPathMTU: Int32 = 43, ipv6PathMTU: Int32 = 44,
               ipv6PktInfo: Int32 = 46, ipv6HopLimit: Int32 = 47, ipv6RecvPktInfo: Int32 = 61,
               ipv6DontFrag: Int32 = 62, ipv6PreferTempAddr: Int32 = 63, ipv6BoundIF: Int32 = 125

    static let tcpNoDelay: Int32 = 1, tcpMaxSeg: Int32 = 2, tcpNoPush: Int32 = 4, tcpNoOpt: Int32 = 8,
               tcpKeepAlive: Int32 = 0x10, tcpConnectionTimeout: Int32 = 0x20, tcpRxtConnDropTime: Int32 = 0x80,
               tcpKeepIntvl: Int32 = 0x101, tcpKeepCnt: Int32 = 0x102, tcpFastOpen: Int32 = 0x105,
               tcpConnectionInfo: Int32 = 0x106, tcpNotSentLowat: Int32 = 0x201

    static let msgOOB: Int32 = 0x1, msgPeek: Int32 = 0x2, msgDontRoute: Int32 = 0x4, msgEOR: Int32 = 0x8,
               msgTrunc: Int32 = 0x10, msgCtrunc: Int32 = 0x20, msgWaitAll: Int32 = 0x40, msgDontWait: Int32 = 0x80,
               msgEOF: Int32 = 0x100, msgNoSignal: Int32 = 0x80000

    static let sockaddrInLength = 16, sockaddrIn6Length = 28
    static let tcpConnectionInfoLength = 112
    static let tcpsClosed: UInt8 = 0, tcpsListen: UInt8 = 1, tcpsSynSent: UInt8 = 2, tcpsSynReceived: UInt8 = 3,
               tcpsEstablished: UInt8 = 4, tcpsCloseWait: UInt8 = 5, tcpsFinWait1: UInt8 = 6, tcpsClosing: UInt8 = 7,
               tcpsLastAck: UInt8 = 8, tcpsFinWait2: UInt8 = 9, tcpsTimeWait: UInt8 = 10
}

enum HostNet {
    #if canImport(Darwin)
    static let isLinux = false
    static let afInet: Int32 = 2, afInet6: Int32 = 30
    static let solSocket: Int32 = 0xFFFF
    static let msgOOB: Int32 = 0x1, msgPeek: Int32 = 0x2, msgDontRoute: Int32 = 0x4, msgCtrunc: Int32 = 0x20,
               msgTrunc: Int32 = 0x10, msgDontWait: Int32 = 0x80, msgEOR: Int32 = 0x8, msgWaitAll: Int32 = 0x40,
               msgNoSignal: Int32 = 0
    static let cmsgHeaderSize = 12, cmsgAlign = 4
    static let fionread: UInt = 0x4004_667F
    #else
    static let isLinux = true
    static let afInet: Int32 = 2, afInet6: Int32 = 10
    static let solSocket: Int32 = 1
    static let msgOOB: Int32 = 0x1, msgPeek: Int32 = 0x2, msgDontRoute: Int32 = 0x4, msgCtrunc: Int32 = 0x8,
               msgTrunc: Int32 = 0x20, msgDontWait: Int32 = 0x40, msgEOR: Int32 = 0x80, msgWaitAll: Int32 = 0x100,
               msgNoSignal: Int32 = 0x4000
    static let cmsgHeaderSize = 16, cmsgAlign = 8
    static let fionread: UInt = 0x541B
    static let siocOutQ: UInt = 0x5411
    static let soDebug: Int32 = 1, soReuseAddr: Int32 = 2, soType: Int32 = 3, soError: Int32 = 4, soDontRoute: Int32 = 5,
               soBroadcast: Int32 = 6, soSndBuf: Int32 = 7, soRcvBuf: Int32 = 8, soKeepAlive: Int32 = 9,
               soOOBInline: Int32 = 10, soLinger: Int32 = 13, soReusePort: Int32 = 15, soRcvLowat: Int32 = 18,
               soTimestamp: Int32 = 29, soAcceptConn: Int32 = 30, soBindToIfIndex: Int32 = 62
    static let scmTimestamp: Int32 = 29
    static let ipTOS: Int32 = 1, ipTTL: Int32 = 2, ipHdrIncl: Int32 = 3, ipOptions: Int32 = 4, ipRecvOpts: Int32 = 6,
               ipRetOpts: Int32 = 7, ipPktInfo: Int32 = 8, ipMTUDiscover: Int32 = 10, ipRecvTTL: Int32 = 12,
               ipRecvTOS: Int32 = 13, ipMulticastIF: Int32 = 32, ipMulticastTTL: Int32 = 33, ipMulticastLoop: Int32 = 34,
               ipAddMembership: Int32 = 35, ipDropMembership: Int32 = 36, ipUnblockSource: Int32 = 37,
               ipBlockSource: Int32 = 38, ipAddSourceMembership: Int32 = 39, ipDropSourceMembership: Int32 = 40
    static let ipPMTUDiscDont: Int32 = 0, ipPMTUDiscDo: Int32 = 2
    static let ipv6Checksum: Int32 = 7, ipv6UnicastHops: Int32 = 16, ipv6MulticastIF: Int32 = 17,
               ipv6MulticastHops: Int32 = 18, ipv6MulticastLoop: Int32 = 19, ipv6JoinGroup: Int32 = 20,
               ipv6LeaveGroup: Int32 = 21, ipv6V6Only: Int32 = 26, ipv6RecvPktInfo: Int32 = 49, ipv6PktInfo: Int32 = 50,
               ipv6RecvHopLimit: Int32 = 51, ipv6HopLimit: Int32 = 52, ipv6RecvPathMTU: Int32 = 60,
               ipv6PathMTU: Int32 = 61, ipv6DontFrag: Int32 = 62, ipv6RecvTClass: Int32 = 66, ipv6TClass: Int32 = 67
    static let tcpNoDelay: Int32 = 1, tcpMaxSeg: Int32 = 2, tcpKeepIdle: Int32 = 4, tcpKeepIntvl: Int32 = 5,
               tcpKeepCnt: Int32 = 6, tcpInfo: Int32 = 11, tcpUserTimeout: Int32 = 18, tcpFastOpen: Int32 = 23,
               tcpNotSentLowat: Int32 = 25
    #endif
}

struct InetAddress: Equatable, CustomStringConvertible {
    var family: Int32
    var port: UInt16
    var address: [UInt8]
    var flowInfo: UInt32 = 0
    var scope: UInt32 = 0

    static func ipv4(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8, port: UInt16) -> InetAddress {
        InetAddress(family: InetABI.afInet, port: port, address: [a, b, c, d])
    }

    var isIPv4: Bool { family == InetABI.afInet }

    var description: String {
        if isIPv4 { return address.map(String.init).joined(separator: ".") + ":\(port)" }
        var groups: [String] = []
        for i in stride(from: 0, to: 16, by: 2) { groups.append(String(UInt16(address[i]) << 8 | UInt16(address[i + 1]), radix: 16)) }
        return "[" + groups.joined(separator: ":") + (scope != 0 ? "%\(scope)" : "") + "]:\(port)"
    }

    static func fromDarwin(_ bytes: [UInt8], domain: Int32) throws -> InetAddress {
        guard bytes.count >= 2 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        let family = Int32(bytes[1])
        switch family {
        case InetABI.afInet:
            guard bytes.count >= InetABI.sockaddrInLength else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            guard domain == InetABI.afInet else { throw DarwinErrnoError(DarwinErrnoCode.EAFNOSUPPORT) }
            return InetAddress(family: family, port: UInt16(bytes[2]) << 8 | UInt16(bytes[3]), address: Array(bytes[4..<8]))
        case InetABI.afInet6:
            guard bytes.count >= InetABI.sockaddrIn6Length else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            guard domain == InetABI.afInet6 else { throw DarwinErrnoError(DarwinErrnoCode.EAFNOSUPPORT) }
            return InetAddress(family: family, port: UInt16(bytes[2]) << 8 | UInt16(bytes[3]),
                               address: Array(bytes[8..<24]), flowInfo: bytes.readBE32(at: 4),
                               scope: bytes.readLE(UInt32.self, at: 24))
        default:
            throw DarwinErrnoError(DarwinErrnoCode.EAFNOSUPPORT)
        }
    }

    var darwinBytes: [UInt8] {
        var b: [UInt8]
        if isIPv4 {
            b = [UInt8(InetABI.sockaddrInLength), UInt8(InetABI.afInet), UInt8(port >> 8), UInt8(port & 0xFF)]
            b += address.prefix(4)
            b += [UInt8](repeating: 0, count: 8)
        } else {
            b = [UInt8(InetABI.sockaddrIn6Length), UInt8(InetABI.afInet6), UInt8(port >> 8), UInt8(port & 0xFF)]
            b.appendBE32(flowInfo)
            b += address.prefix(16)
            b.appendLE(scope)
        }
        return b
    }

    func hostBytes(hostScope: UInt32) -> [UInt8] {
        var b: [UInt8]
        let fam = isIPv4 ? HostNet.afInet : HostNet.afInet6
        #if canImport(Darwin)
        b = [UInt8(isIPv4 ? 16 : 28), UInt8(fam)]
        #else
        b = []
        b.appendLE(UInt16(fam))
        #endif
        b += [UInt8(port >> 8), UInt8(port & 0xFF)]
        if isIPv4 {
            b += address.prefix(4)
            b += [UInt8](repeating: 0, count: 8)
        } else {
            b.appendBE32(flowInfo)
            b += address.prefix(16)
            b.appendLE(hostScope)
        }
        return b
    }

    static func fromHost(_ b: [UInt8], guestScope: (UInt32) -> UInt32) -> InetAddress? {
        guard b.count >= 2 else { return nil }
        #if canImport(Darwin)
        let fam = Int32(b[1])
        #else
        let fam = Int32(b.readLE(UInt16.self, at: 0))
        #endif
        let port = b.count >= 4 ? UInt16(b[2]) << 8 | UInt16(b[3]) : 0
        if fam == HostNet.afInet, b.count >= 8 {
            return InetAddress(family: InetABI.afInet, port: port, address: Array(b[4..<8]))
        }
        if fam == HostNet.afInet6, b.count >= 24 {
            let hostScope = b.count >= 28 ? b.readLE(UInt32.self, at: 24) : 0
            return InetAddress(family: InetABI.afInet6, port: port, address: Array(b[8..<24]),
                               flowInfo: b.readBE32(at: 4), scope: hostScope == 0 ? 0 : guestScope(hostScope))
        }
        return nil
    }

    static func unspecified(_ family: Int32) -> InetAddress {
        InetAddress(family: family, port: 0, address: [UInt8](repeating: 0, count: family == InetABI.afInet ? 4 : 16))
    }
}

extension Array where Element == UInt8 {
    func readBE32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset]) << 24 | UInt32(self[offset + 1]) << 16 | UInt32(self[offset + 2]) << 8 | UInt32(self[offset + 3])
    }

    func readBE16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) << 8 | UInt16(self[offset + 1])
    }

    mutating func appendBE32(_ v: UInt32) {
        append(UInt8(v >> 24)); append(UInt8((v >> 16) & 0xFF)); append(UInt8((v >> 8) & 0xFF)); append(UInt8(v & 0xFF))
    }

    mutating func appendBE16(_ v: UInt16) {
        append(UInt8(v >> 8)); append(UInt8(v & 0xFF))
    }
}

enum SocketErrno {
    static func fromHost(_ e: Int32) -> Int32 {
        #if canImport(Darwin)
        return e
        #else
        switch e {
        case 11: return 35
        case 35: return 11
        case 36: return 63
        case 40: return 62
        case 71: return 100
        case 75: return 84
        case 88: return 38
        case 89: return 39
        case 90: return 40
        case 91: return 41
        case 92: return 42
        case 93: return 43
        case 94: return 44
        case 95: return 102
        case 96: return 46
        case 97: return 47
        case 98: return 48
        case 99: return 49
        case 100: return 50
        case 101: return 51
        case 102: return 52
        case 103: return 53
        case 104: return 54
        case 105: return 55
        case 106: return 56
        case 107: return 57
        case 108: return 58
        case 109: return 59
        case 110: return 60
        case 111: return 61
        case 112: return 64
        case 113: return 65
        case 114: return 37
        case 115: return 36
        case 125: return 89
        case 1...34: return e
        default: return 5
        }
        #endif
    }

    static let EINPROGRESS: Int32 = 36, EALREADY: Int32 = 37, EADDRNOTAVAIL: Int32 = 49, ENETUNREACH: Int32 = 51,
               EHOSTUNREACH: Int32 = 65, EAGAIN: Int32 = 35, EISCONN: Int32 = 56, ENOTCONN: Int32 = 57,
               EPIPE: Int32 = 32, ECONNRESET: Int32 = 54, EINVAL: Int32 = 22, ENOPROTOOPT: Int32 = 42,
               EOPNOTSUPP: Int32 = 102, EMSGSIZE: Int32 = 40, EPERM: Int32 = 1, EACCES: Int32 = 13

    static func last() -> DarwinErrnoError { DarwinErrnoError(fromHost(errno)) }
}

enum SocketFlags {
    static func hostCallFlags(_ f: Int32) -> Int32 {
        var h: Int32 = HostNet.msgDontWait | HostNet.msgNoSignal
        if f & InetABI.msgOOB != 0 { h |= HostNet.msgOOB }
        if f & InetABI.msgPeek != 0 { h |= HostNet.msgPeek }
        if f & InetABI.msgDontRoute != 0 { h |= HostNet.msgDontRoute }
        if f & InetABI.msgEOR != 0 { h |= HostNet.msgEOR }
        return h
    }

    static func darwinReceivedFlags(_ h: Int32) -> Int32 {
        var f: Int32 = 0
        if h & HostNet.msgTrunc != 0 { f |= InetABI.msgTrunc }
        if h & HostNet.msgCtrunc != 0 { f |= InetABI.msgCtrunc }
        if h & HostNet.msgOOB != 0 { f |= InetABI.msgOOB }
        if h & HostNet.msgEOR != 0 { f |= InetABI.msgEOR }
        return f
    }
}

enum SocketOptionRoute: Equatable {
    case host(level: Int32, name: Int32, kind: SocketOptionValue)
    case local
}

enum SocketOptionValue: Equatable {
    case int
    case uchar
    case linger(ticks: Bool)
    case ifIndex
    case ipMreq
    case ipv6Mreq
    case in6PktInfo
    case dontFrag
    case secondsToMilliseconds
    case raw
}

enum SocketOptions {
    static func route(level: Int32, name: Int32) -> SocketOptionRoute {
        #if canImport(Darwin)
        switch (level, name) {
        case (InetABI.solSocket, InetABI.soSndTimeo), (InetABI.solSocket, InetABI.soRcvTimeo),
             (InetABI.solSocket, InetABI.soNoSigPipe):
            return .local
        default:
            return .host(level: level, name: name, kind: .raw)
        }
        #else
        switch level {
        case InetABI.solSocket:
            switch name {
            case InetABI.soDebug: return .host(level: HostNet.solSocket, name: HostNet.soDebug, kind: .int)
            case InetABI.soAcceptConn: return .host(level: HostNet.solSocket, name: HostNet.soAcceptConn, kind: .int)
            case InetABI.soReuseAddr: return .host(level: HostNet.solSocket, name: HostNet.soReuseAddr, kind: .int)
            case InetABI.soKeepAlive: return .host(level: HostNet.solSocket, name: HostNet.soKeepAlive, kind: .int)
            case InetABI.soDontRoute: return .host(level: HostNet.solSocket, name: HostNet.soDontRoute, kind: .int)
            case InetABI.soBroadcast: return .host(level: HostNet.solSocket, name: HostNet.soBroadcast, kind: .int)
            case InetABI.soLinger: return .host(level: HostNet.solSocket, name: HostNet.soLinger, kind: .linger(ticks: true))
            case InetABI.soLingerSec: return .host(level: HostNet.solSocket, name: HostNet.soLinger, kind: .linger(ticks: false))
            case InetABI.soOOBInline: return .host(level: HostNet.solSocket, name: HostNet.soOOBInline, kind: .int)
            case InetABI.soReusePort: return .host(level: HostNet.solSocket, name: HostNet.soReusePort, kind: .int)
            case InetABI.soTimestamp: return .host(level: HostNet.solSocket, name: HostNet.soTimestamp, kind: .int)
            case InetABI.soSndBuf: return .host(level: HostNet.solSocket, name: HostNet.soSndBuf, kind: .int)
            case InetABI.soRcvBuf: return .host(level: HostNet.solSocket, name: HostNet.soRcvBuf, kind: .int)
            case InetABI.soRcvLowat: return .host(level: HostNet.solSocket, name: HostNet.soRcvLowat, kind: .int)
            default: return .local
            }
        case InetABI.ipprotoIP:
            let L = InetABI.ipprotoIP
            switch name {
            case InetABI.ipOptions: return .host(level: L, name: HostNet.ipOptions, kind: .raw)
            case InetABI.ipHdrIncl: return .host(level: L, name: HostNet.ipHdrIncl, kind: .int)
            case InetABI.ipTOS: return .host(level: L, name: HostNet.ipTOS, kind: .int)
            case InetABI.ipTTL: return .host(level: L, name: HostNet.ipTTL, kind: .int)
            case InetABI.ipRecvOpts: return .host(level: L, name: HostNet.ipRecvOpts, kind: .int)
            case InetABI.ipRecvRetOpts: return .host(level: L, name: HostNet.ipRetOpts, kind: .int)
            case InetABI.ipMulticastIF: return .host(level: L, name: HostNet.ipMulticastIF, kind: .ipMreq)
            case InetABI.ipMulticastTTL: return .host(level: L, name: HostNet.ipMulticastTTL, kind: .uchar)
            case InetABI.ipMulticastLoop: return .host(level: L, name: HostNet.ipMulticastLoop, kind: .uchar)
            case InetABI.ipAddMembership: return .host(level: L, name: HostNet.ipAddMembership, kind: .ipMreq)
            case InetABI.ipDropMembership: return .host(level: L, name: HostNet.ipDropMembership, kind: .ipMreq)
            case InetABI.ipAddSourceMembership: return .host(level: L, name: HostNet.ipAddSourceMembership, kind: .raw)
            case InetABI.ipDropSourceMembership: return .host(level: L, name: HostNet.ipDropSourceMembership, kind: .raw)
            case InetABI.ipBlockSource: return .host(level: L, name: HostNet.ipBlockSource, kind: .raw)
            case InetABI.ipUnblockSource: return .host(level: L, name: HostNet.ipUnblockSource, kind: .raw)
            case InetABI.ipRecvTTL: return .host(level: L, name: HostNet.ipRecvTTL, kind: .int)
            case InetABI.ipRecvTOS: return .host(level: L, name: HostNet.ipRecvTOS, kind: .int)
            case InetABI.ipDontFrag: return .host(level: L, name: HostNet.ipMTUDiscover, kind: .dontFrag)
            default: return .local
            }
        case InetABI.ipprotoIPv6:
            let L = InetABI.ipprotoIPv6
            switch name {
            case InetABI.ipv6UnicastHops: return .host(level: L, name: HostNet.ipv6UnicastHops, kind: .int)
            case InetABI.ipv6MulticastIF: return .host(level: L, name: HostNet.ipv6MulticastIF, kind: .ifIndex)
            case InetABI.ipv6MulticastHops: return .host(level: L, name: HostNet.ipv6MulticastHops, kind: .int)
            case InetABI.ipv6MulticastLoop: return .host(level: L, name: HostNet.ipv6MulticastLoop, kind: .int)
            case InetABI.ipv6JoinGroup: return .host(level: L, name: HostNet.ipv6JoinGroup, kind: .ipv6Mreq)
            case InetABI.ipv6LeaveGroup: return .host(level: L, name: HostNet.ipv6LeaveGroup, kind: .ipv6Mreq)
            case InetABI.ipv6Checksum: return .host(level: L, name: HostNet.ipv6Checksum, kind: .int)
            case InetABI.ipv6V6Only: return .host(level: L, name: HostNet.ipv6V6Only, kind: .int)
            case InetABI.ipv6RecvTClass: return .host(level: L, name: HostNet.ipv6RecvTClass, kind: .int)
            case InetABI.ipv6TClass: return .host(level: L, name: HostNet.ipv6TClass, kind: .int)
            case InetABI.ipv6RecvHopLimit: return .host(level: L, name: HostNet.ipv6RecvHopLimit, kind: .int)
            case InetABI.ipv6HopLimit: return .host(level: L, name: HostNet.ipv6HopLimit, kind: .int)
            case InetABI.ipv6RecvPktInfo: return .host(level: L, name: HostNet.ipv6RecvPktInfo, kind: .int)
            case InetABI.ipv6PktInfo: return .host(level: L, name: HostNet.ipv6PktInfo, kind: .in6PktInfo)
            case InetABI.ipv6DontFrag: return .host(level: L, name: HostNet.ipv6DontFrag, kind: .int)
            case InetABI.ipv6RecvPathMTU: return .host(level: L, name: HostNet.ipv6RecvPathMTU, kind: .int)
            case InetABI.ipv6PathMTU: return .host(level: L, name: HostNet.ipv6PathMTU, kind: .raw)
            default: return .local
            }
        case InetABI.ipprotoTCP:
            let L = InetABI.ipprotoTCP
            switch name {
            case InetABI.tcpNoDelay: return .host(level: L, name: HostNet.tcpNoDelay, kind: .int)
            case InetABI.tcpMaxSeg: return .host(level: L, name: HostNet.tcpMaxSeg, kind: .int)
            case InetABI.tcpKeepAlive: return .host(level: L, name: HostNet.tcpKeepIdle, kind: .int)
            case InetABI.tcpKeepIntvl: return .host(level: L, name: HostNet.tcpKeepIntvl, kind: .int)
            case InetABI.tcpKeepCnt: return .host(level: L, name: HostNet.tcpKeepCnt, kind: .int)
            case InetABI.tcpNotSentLowat: return .host(level: L, name: HostNet.tcpNotSentLowat, kind: .int)
            case InetABI.tcpRxtConnDropTime:
                return .host(level: L, name: HostNet.tcpUserTimeout, kind: .secondsToMilliseconds)
            default: return .local
            }
        default:
            return .local
        }
        #endif
    }

    static func hostValue(_ v: [UInt8], kind: SocketOptionValue, hostIndex: (UInt32) -> UInt32) throws -> [UInt8] {
        func need(_ n: Int) throws { guard v.count >= n else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) } }
        switch kind {
        case .int:
            try need(4)
            return Array(v.prefix(4))
        case .uchar:
            try need(1)
            var b: [UInt8] = []
            b.appendLE(Int32(v.count >= 4 ? v.readLE(Int32.self, at: 0) : Int32(v[0])))
            return b
        case let .linger(ticks):
            try need(8)
            var b: [UInt8] = []
            b.appendLE(v.readLE(Int32.self, at: 0))
            let t = v.readLE(Int32.self, at: 4)
            b.appendLE(ticks ? (t <= 0 ? t : (t + 99) / 100) : t)
            return b
        case .ifIndex:
            try need(4)
            var b: [UInt8] = []
            b.appendLE(hostIndex(v.readLE(UInt32.self, at: 0)))
            return b
        case .ipMreq:
            try need(4)
            var b = v
            if v.count >= 12 { b.putLE(hostIndex(v.readLE(UInt32.self, at: 8)), at: 8) }
            return b
        case .ipv6Mreq, .in6PktInfo:
            try need(20)
            var b = Array(v.prefix(20))
            b.putLE(hostIndex(v.readLE(UInt32.self, at: 16)), at: 16)
            return b
        case .dontFrag:
            try need(4)
            var b: [UInt8] = []
            #if canImport(Darwin)
            b = Array(v.prefix(4))
            #else
            b.appendLE(v.readLE(Int32.self, at: 0) != 0 ? HostNet.ipPMTUDiscDo : HostNet.ipPMTUDiscDont)
            #endif
            return b
        case .secondsToMilliseconds:
            try need(4)
            var b: [UInt8] = []
            let s = Int64(v.readLE(Int32.self, at: 0))
            b.appendLE(UInt32(clamping: max(0, s) * 1000))
            return b
        case .raw:
            return v
        }
    }

    static func guestValue(_ v: [UInt8], kind: SocketOptionValue, guestIndex: (UInt32) -> UInt32) -> [UInt8] {
        switch kind {
        case .int:
            return Array(v.prefix(4)) + [UInt8](repeating: 0, count: max(0, 4 - v.count))
        case .uchar:
            return [v.first ?? 0]
        case let .linger(ticks):
            var b: [UInt8] = []
            b.appendLE(v.readLE(Int32.self, at: 0))
            let s = v.readLE(Int32.self, at: 4)
            b.appendLE(ticks ? s &* 100 : s)
            return b
        case .ifIndex:
            var b: [UInt8] = []
            b.appendLE(guestIndex(v.readLE(UInt32.self, at: 0)))
            return b
        case .ipMreq, .raw:
            return v
        case .ipv6Mreq, .in6PktInfo:
            var b = v
            if b.count >= 20 { b.putLE(guestIndex(v.readLE(UInt32.self, at: 16)), at: 16) }
            return b
        case .dontFrag:
            var b: [UInt8] = []
            #if canImport(Darwin)
            b = Array(v.prefix(4))
            #else
            b.appendLE(Int32(v.readLE(Int32.self, at: 0) == HostNet.ipPMTUDiscDo ? 1 : 0))
            #endif
            return b
        case .secondsToMilliseconds:
            var b: [UInt8] = []
            b.appendLE(Int32(clamping: Int64(v.readLE(UInt32.self, at: 0)) / 1000))
            return b
        }
    }
}

struct ControlMessage: Equatable {
    var level: Int32
    var type: Int32
    var data: [UInt8]
}

enum ControlMessages {
    static func parseDarwin(_ b: [UInt8]) throws -> [ControlMessage] {
        var out: [ControlMessage] = []
        var off = 0
        while off + 12 <= b.count {
            let len = Int(b.readLE(UInt32.self, at: off))
            guard len >= 12, off + len <= b.count else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            out.append(ControlMessage(level: b.readLE(Int32.self, at: off + 4), type: b.readLE(Int32.self, at: off + 8),
                                      data: Array(b[(off + 12)..<(off + len)])))
            off += (len + 3) & ~3
        }
        return out
    }

    static func encodeDarwin(_ ms: [ControlMessage], room: Int) -> (bytes: [UInt8], truncated: Bool) {
        var b: [UInt8] = []
        for m in ms {
            let len = 12 + m.data.count
            let space = (len + 3) & ~3
            guard b.count + len <= room else { return (b, true) }
            b.appendLE(UInt32(len))
            b.appendLE(m.level)
            b.appendLE(m.type)
            b += m.data
            if b.count + (space - len) <= room { b += [UInt8](repeating: 0, count: space - len) }
        }
        return (b, false)
    }

    static func parseHost(_ b: [UInt8]) -> [ControlMessage] {
        var out: [ControlMessage] = []
        var off = 0
        let header = HostNet.cmsgHeaderSize, align = HostNet.cmsgAlign
        while off + header <= b.count {
            let len = header == 16 ? Int(b.readLE(UInt64.self, at: off)) : Int(b.readLE(UInt32.self, at: off))
            guard len >= header, off + len <= b.count else { break }
            let lvl = b.readLE(Int32.self, at: off + header - 8), typ = b.readLE(Int32.self, at: off + header - 4)
            out.append(ControlMessage(level: lvl, type: typ, data: Array(b[(off + header)..<(off + len)])))
            off += (len + align - 1) & ~(align - 1)
        }
        return out
    }

    static func encodeHost(_ ms: [ControlMessage]) -> [UInt8] {
        var b: [UInt8] = []
        let header = HostNet.cmsgHeaderSize, align = HostNet.cmsgAlign
        for m in ms {
            let len = header + m.data.count
            if header == 16 { b.appendLE(UInt64(len)) } else { b.appendLE(UInt32(len)) }
            b.appendLE(m.level)
            b.appendLE(m.type)
            b += m.data
            while b.count % align != 0 { b.append(0) }
        }
        return b
    }

    struct ReceiveWants: Equatable {
        var dstAddr = false
        var pktInfo = false
        var recvIF = false
        var ttl = false
        var tos = false
    }

    static func darwinReceived(_ ms: [ControlMessage], wants: ReceiveWants,
                               guestIndex: (UInt32) -> UInt32,
                               interfaceName: (UInt32) -> String?) -> [ControlMessage] {
        #if canImport(Darwin)
        return ms
        #else
        var out: [ControlMessage] = []
        for m in ms {
            switch (m.level, m.type) {
            case (HostNet.solSocket, HostNet.scmTimestamp) where m.data.count >= 16:
                var d: [UInt8] = []
                d.appendLE(m.data.readLE(Int64.self, at: 0))
                d.appendLE(Int32(truncatingIfNeeded: m.data.readLE(Int64.self, at: 8)))
                d.appendLE(Int32(0))
                out.append(ControlMessage(level: InetABI.solSocket, type: InetABI.scmTimestamp, data: d))
            case (InetABI.ipprotoIP, HostNet.ipPktInfo) where m.data.count >= 12:
                let index = guestIndex(m.data.readLE(UInt32.self, at: 0))
                if wants.dstAddr {
                    out.append(ControlMessage(level: InetABI.ipprotoIP, type: InetABI.ipRecvDstAddr, data: Array(m.data[8..<12])))
                }
                if wants.recvIF {
                    out.append(ControlMessage(level: InetABI.ipprotoIP, type: InetABI.ipRecvIF,
                                              data: NetworkInterfaces.sockaddrDL(index: index, name: interfaceName(index) ?? "",
                                                                                 type: 0, address: [])))
                }
                if wants.pktInfo {
                    var d = Array(m.data.prefix(12))
                    d.putLE(index, at: 0)
                    out.append(ControlMessage(level: InetABI.ipprotoIP, type: InetABI.ipPktInfo, data: d))
                }
            case (InetABI.ipprotoIP, HostNet.ipTTL) where !m.data.isEmpty:
                out.append(ControlMessage(level: InetABI.ipprotoIP, type: InetABI.ipRecvTTL, data: [m.data[0]]))
            case (InetABI.ipprotoIP, HostNet.ipTOS) where !m.data.isEmpty:
                out.append(ControlMessage(level: InetABI.ipprotoIP, type: InetABI.ipRecvTOS, data: [m.data[0]]))
            case (InetABI.ipprotoIPv6, HostNet.ipv6PktInfo) where m.data.count >= 20:
                var d = Array(m.data.prefix(20))
                d.putLE(guestIndex(m.data.readLE(UInt32.self, at: 16)), at: 16)
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: InetABI.ipv6PktInfo, data: d))
            case (InetABI.ipprotoIPv6, HostNet.ipv6HopLimit):
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: InetABI.ipv6HopLimit, data: Array(m.data.prefix(4))))
            case (InetABI.ipprotoIPv6, HostNet.ipv6TClass):
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: InetABI.ipv6TClass, data: Array(m.data.prefix(4))))
            case (InetABI.ipprotoIPv6, HostNet.ipv6PathMTU):
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: InetABI.ipv6PathMTU, data: m.data))
            default:
                break
            }
        }
        return out
        #endif
    }

    static func hostSent(_ ms: [ControlMessage], hostIndex: (UInt32) -> UInt32) throws -> [ControlMessage] {
        var out: [ControlMessage] = []
        for m in ms {
            if m.level == InetABI.solSocket, m.type == InetABI.scmRights { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            #if canImport(Darwin)
            out.append(m)
            #else
            switch (m.level, m.type) {
            case (InetABI.ipprotoIP, InetABI.ipPktInfo) where m.data.count >= 12:
                var d = Array(m.data.prefix(12))
                d.putLE(hostIndex(m.data.readLE(UInt32.self, at: 0)), at: 0)
                out.append(ControlMessage(level: InetABI.ipprotoIP, type: HostNet.ipPktInfo, data: d))
            case (InetABI.ipprotoIP, InetABI.ipTOS):
                var d: [UInt8] = []
                d.appendLE(Int32(m.data.count >= 4 ? m.data.readLE(Int32.self, at: 0) : Int32(m.data.first ?? 0)))
                out.append(ControlMessage(level: InetABI.ipprotoIP, type: HostNet.ipTOS, data: d))
            case (InetABI.ipprotoIP, InetABI.ipTTL):
                var d: [UInt8] = []
                d.appendLE(Int32(m.data.count >= 4 ? m.data.readLE(Int32.self, at: 0) : Int32(m.data.first ?? 0)))
                out.append(ControlMessage(level: InetABI.ipprotoIP, type: HostNet.ipTTL, data: d))
            case (InetABI.ipprotoIPv6, InetABI.ipv6PktInfo) where m.data.count >= 20:
                var d = Array(m.data.prefix(20))
                d.putLE(hostIndex(m.data.readLE(UInt32.self, at: 16)), at: 16)
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: HostNet.ipv6PktInfo, data: d))
            case (InetABI.ipprotoIPv6, InetABI.ipv6TClass):
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: HostNet.ipv6TClass, data: m.data))
            case (InetABI.ipprotoIPv6, InetABI.ipv6HopLimit):
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: HostNet.ipv6HopLimit, data: m.data))
            case (InetABI.ipprotoIPv6, InetABI.ipv6DontFrag):
                out.append(ControlMessage(level: InetABI.ipprotoIPv6, type: HostNet.ipv6DontFrag, data: m.data))
            default:
                break
            }
            #endif
        }
        return out
    }
}
