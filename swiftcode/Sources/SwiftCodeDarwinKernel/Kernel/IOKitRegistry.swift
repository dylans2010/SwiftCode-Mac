import SwiftCodeDarwinABI

final class IOKitObject {
    enum Kind {
        case entry(className: String, name: String, path: String, superclasses: [String], entryID: UInt64)
        case iterator(entries: [IPCPort], next: Int)
        case notification
        case connection(service: IPCPort, type: UInt32)
    }
    var kind: Kind
    init(_ kind: Kind) { self.kind = kind }
}

enum IOReturn {
    static let notFound: UInt32 = 0xE000_02F0
    static let noDevice: UInt32 = 0xE000_02C0
    static let unsupported: UInt32 = 0xE000_02C7
}

extension MachIPCSystem {
    func ioKitMainPort() -> IPCPort {
        if let p = ioMain { return p }
        let p = IPCPort(serial: nextSerial())
        p.kernelObject = .ioMain
        ioMain = p
        let root = IPCPort(serial: nextSerial())
        root.kernelObject = .ioObject(serial: root.serial)
        ioObjects[root.serial] = IOKitObject(.entry(className: "IOPMrootDomain", name: "IOPMrootDomain",
                                                    path: "IOPower:/IOPowerConnection/IOPMrootDomain",
                                                    superclasses: ["IOService", "IORegistryEntry", "OSObject"],
                                                    entryID: 0x1_0000_0101))
        ioRegistryPaths["IOPower:/IOPowerConnection/IOPMrootDomain"] = root
        return p
    }
}

extension MachIPC {
    private func ioRight(_ p: IPCPort?) -> KItem {
        guard let p else { return .port(.null, type: MachMsgType.portSend) }
        p.srights += 1
        return .port(.send(p), type: MachMsgType.portSend)
    }

    private func ioObjectPort(_ object: IOKitObject) -> IPCPort {
        let p = newPort()
        p.kernelObject = .ioObject(serial: p.serial)
        system.ioObjects[p.serial] = object
        return p
    }

    private func migString(_ s: String) -> [UInt8] {
        var bytes = Array(s.utf8) + [0]
        let count = UInt32(bytes.count)
        while bytes.count % 4 != 0 { bytes.append(0) }
        return le32(0) + le32(count) + bytes
    }

    func ioKitServer(_ m: inout KMessage, port p: IPCPort) -> MIGReply? {
        let b = m.inline
        let size = m.size
        func u32(_ at: Int) -> UInt32 {
            let o = at - (size - b.count)
            return o >= 0 && o + 4 <= b.count ? b.readLE(UInt32.self, at: o) : 0
        }
        func string(_ at: Int) -> String? {
            let count = Int(u32(at + 4))
            let o = at + 8 - (size - b.count)
            guard count > 0, o >= 0, o + count <= b.count else { return nil }
            return String(decoding: b[o..<(o + count)].prefix { $0 != 0 }, as: UTF8.self)
        }
        let object = system.ioObjects[p.serial]
        switch (m.id, p.kernelObject) {
        case (2809, .ioMain?):
            guard let path = string(32) else { return .error(MachKern.migBadArguments) }
            _ = system.ioKitMainPort()
            return MIGReply(inline: [], items: [ioRight(system.ioRegistryPaths[path])])
        case (2804, .ioMain?), (2857, .ioMain?):
            if m.id == 2857 { return .error(IOReturn.unsupported) }
            return MIGReply(inline: [], items: [ioRight(ioObjectPort(IOKitObject(.iterator(entries: [], next: 0))))])
        case (2873, .ioMain?), (2874, .ioMain?):
            return .error(IOReturn.notFound)
        case (2868, .ioMain?), (2870, .ioMain?), (2884, .ioMain?):
            return MIGReply(inline: m.id == 2870 ? machNDRRecord + le32(0) : [],
                            items: [ioRight(ioObjectPort(IOKitObject(.notification)))])
        case (2806, .ioMain?):
            return MIGReply(inline: [], items: [ioRight(ioObjectPort(IOKitObject(.iterator(entries: [], next: 0))))])
        case (2827, .ioMain?):
            return .error(IOReturn.notFound)
        default:
            break
        }
        guard let object else { return .error(MachKern.migBadID) }
        switch (m.id, object.kind) {
        case let (2800, .entry(className, _, _, _, _)):
            return .simple(0, migString(className))
        case (2800, .iterator):
            return .simple(0, migString("IOUserIterator"))
        case (2800, .notification):
            return .simple(0, migString("IOUserNotification"))
        case let (2801, .entry(className, _, _, superclasses, _)):
            let asked = string(32) ?? ""
            return .simple(0, le32(asked == className || superclasses.contains(asked) ? 1 : 0))
        case (2801, _):
            return .simple(0, le32(0))
        case (2802, .iterator(let entries, let next)):
            guard next < entries.count else { return .error(IOReturn.noDevice) }
            object.kind = .iterator(entries: entries, next: next + 1)
            return MIGReply(inline: [], items: [ioRight(entries[next])])
        case (2803, .iterator(let entries, _)):
            object.kind = .iterator(entries: entries, next: 0)
            return .simple(0)
        case (2802, .notification):
            return .error(IOReturn.noDevice)
        case (2834, .iterator), (2834, .notification):
            return .simple(0, le32(1))
        case let (2810, .entry(_, name, _, _, _)), let (2843, .entry(_, name, _, _, _)):
            return .simple(0, migString(name))
        case let (2826, .entry(_, _, path, _, _)):
            return .simple(0, migString(path))
        case let (2871, .entry(_, _, _, _, entryID)):
            return .simple(0, le64(entryID))
        case (2805, .entry), (2855, .entry), (2879, .entry), (2889, .entry):
            return .error(IOReturn.notFound)
        case (2869, .entry), (2850, .entry):
            return MIGReply(inline: [], items: [ioRight(ioObjectPort(IOKitObject(.notification)))])
        case (2862, .entry):
            let type = b.count >= 12 ? b.readLE(UInt32.self, at: 8) : 0
            let connection = ioObjectPort(IOKitObject(.connection(service: p, type: type)))
            return MIGReply(inline: machNDRRecord + le32(0), items: [ioRight(connection)])
        case (2816, .connection):
            return .simple(0)
        case let (2817, .connection(service, _)):
            return MIGReply(inline: [], items: [ioRight(service)])
        case (2867, .connection), (2818, .connection):
            return .simple(0)
        case (2865, .connection):
            let scalarIn = Int(min(u32(36), 16))
            var at = 40 + 8 * scalarIn
            let inband = Int(min(u32(at), 4096))
            at += 4 + ((inband + 3) & ~3) + 16
            let inbandOut = Int(min(u32(at), 4096)), scalarOut = Int(min(u32(at + 4), 16))
            return .simple(0, le32(UInt32(inbandOut)) + [UInt8](repeating: 0, count: (inbandOut + 3) & ~3)
                + le32(UInt32(scalarOut)) + [UInt8](repeating: 0, count: 8 * scalarOut) + le64(0))
        case (2830, _):
            return .simple(0, le32(1))
        case (2831, .entry):
            return .simple(0, le32(0))
        default:
            return .error(MachKern.migBadID)
        }
    }
}
