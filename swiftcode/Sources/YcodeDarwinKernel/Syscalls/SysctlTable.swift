import Foundation

public struct SysctlTable: Sendable {
    public enum Value: Equatable, Sendable {
        case integer(Int64, size: Int)
        case quad(Int64)
        case string(String)
        case error(Int32)
        case bytes([UInt8])

        public enum Answer: Equatable, Sendable {
            case bytes([UInt8])
            case failure(errno: Int32, length: UInt64?)
        }

        public func answer(forBufferOf oldLength: UInt64?) -> Answer {
            switch self {
            case let .integer(v, size):
                if size == 4 {
                    if let n = oldLength, n < 4 { return .failure(errno: DarwinKernel.Errno.ENOMEM, length: 0) }
                    return .bytes(Self.le32(v))
                }
                guard let n = oldLength else { return .bytes(Self.le64(v)) }
                if n >= 8 { return .bytes(Self.le64(v)) }
                if n == 4 {
                    guard v >= Int64(Int32.min) && v <= Int64(Int32.max) else {
                        return .failure(errno: DarwinKernel.Errno.ERANGE, length: nil)
                    }
                    return .bytes(Self.le32(v))
                }
                return .failure(errno: DarwinKernel.Errno.ENOMEM, length: 0)
            case let .quad(v):
                if let n = oldLength, n < 8 { return .failure(errno: DarwinKernel.Errno.ENOMEM, length: 0) }
                return .bytes(Self.le64(v))
            case let .string(s):
                return .bytes(cString(s))
            case let .bytes(b):
                return .bytes(b)
            case let .error(e):
                return .failure(errno: e, length: nil)
            }
        }

        private static func le32(_ v: Int64) -> [UInt8] {
            var b: [UInt8] = []
            b.appendLE(Int32(truncatingIfNeeded: v))
            return b
        }

        private static func le64(_ v: Int64) -> [UInt8] {
            var b: [UInt8] = []
            b.appendLE(v)
            return b
        }
    }

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var mib: [Int32]
        public var value: Value
    }

    public var entries: [Entry] { didSet { reindex() } }

    public static var standard: SysctlTable { GuestCPUProfile.currentTable }

    static func baseEntries(cpuCount: Int) -> [Entry] {
        let n = Int64(cpuCount)
        return [
        Entry(name: "kern.grade_cputype", mib: [1, 1000], value: .error(DarwinKernel.Errno.ENOENT)),
        Entry(name: "hw.pagesize", mib: [6, 1025], value: .integer(16384, size: 8)),
        Entry(name: "hw.pagesize", mib: [6, 7], value: .integer(16384, size: 4)),
        Entry(name: "hw.ncpu", mib: [6, 3], value: .integer(n, size: 4)),
        Entry(name: "hw.activecpu", mib: [6, 1001], value: .integer(n, size: 4)),
        Entry(name: "kern.osproductversion", mib: [1, 1001], value: .string("27.1")),
        Entry(name: "kern.ostype", mib: [1, 1], value: .string("Darwin")),
        Entry(name: "kern.osrelease", mib: [1, 2], value: .string("26.1.0")),
        Entry(name: "kern.osrevision", mib: [1, 3], value: .integer(199506, size: 4)),
        Entry(name: "kern.version", mib: [1, 4], value: .string("Darwin Kernel Version 26.1.0: SwiftCode micro-VM; root:swiftcode/RELEASE_ARM64")),
        Entry(name: "kern.maxproc", mib: [1, 6], value: .integer(2000, size: 4)),
        Entry(name: "kern.maxfiles", mib: [1, 7], value: .integer(12288, size: 4)),
        Entry(name: "kern.argmax", mib: [1, 8], value: .integer(1 << 20, size: 4)),
        Entry(name: "kern.securelevel", mib: [1, 9], value: .integer(0, size: 4)),
        Entry(name: "kern.hostname", mib: [1, 10], value: .string("swiftcode-sim")),
        Entry(name: "kern.boottime", mib: [1, 21], value: .bytes(SysctlTable.bootTime())),
        Entry(name: "kern.maxfilesperproc", mib: [1, 29], value: .integer(256, size: 4)),
        Entry(name: "kern.usrstack64", mib: [1, 59], value: .integer(Int64(Stage3Layout.userStack), size: 8)),
        Entry(name: "kern.osversion", mib: [1, 65], value: .string("24A94401")),
        Entry(name: "kern.secure_kernel", mib: [1, 1002], value: .integer(0, size: 4)),
        Entry(name: "kern.hv_vmm_present", mib: [1, 1003], value: .integer(0, size: 4)),
        Entry(name: "kern.osvariant_status", mib: [1, 1004], value: .integer(0, size: 8)),
        Entry(name: "hw.machine", mib: [6, 1], value: .string("arm64")),
        Entry(name: "hw.model", mib: [6, 2], value: .string("SwiftCodeVM1,1")),
        Entry(name: "hw.byteorder", mib: [6, 4], value: .integer(1234, size: 4)),
        Entry(name: "hw.physmem", mib: [6, 5], value: .integer(Int64(Stage3Layout.memorySize), size: 4)),
        Entry(name: "hw.usermem", mib: [6, 6], value: .integer(Int64(Stage3Layout.memorySize) / 2, size: 4)),
        Entry(name: "hw.memsize", mib: [6, 24], value: .integer(Int64(Stage3Layout.memorySize), size: 8)),
        Entry(name: "hw.availcpu", mib: [6, 25], value: .integer(n, size: 4)),
        Entry(name: "hw.cputype", mib: [6, 1002], value: .integer(0x0100_000C, size: 4)),
        Entry(name: "hw.cpusubtype", mib: [6, 1003], value: .integer(0, size: 4)),
        Entry(name: "hw.cpu64bit_capable", mib: [6, 1004], value: .integer(1, size: 4)),
        Entry(name: "hw.logicalcpu", mib: [6, 1005], value: .integer(n, size: 4)),
        Entry(name: "hw.logicalcpu_max", mib: [6, 1006], value: .integer(n, size: 4)),
        Entry(name: "hw.physicalcpu", mib: [6, 1007], value: .integer(n, size: 4)),
        Entry(name: "hw.physicalcpu_max", mib: [6, 1008], value: .integer(n, size: 4)),
        Entry(name: "hw.cpufamily", mib: [6, 1009], value: .integer(0, size: 4)),
        Entry(name: "hw.nperflevels", mib: [6, 1010], value: .integer(1, size: 4)),
        Entry(name: "hw.memsize_usable", mib: [6, 1011], value: .integer(Int64(Stage3Layout.memorySize), size: 8)),
        Entry(name: "vm.pagesize", mib: [2, 1000], value: .integer(16384, size: 4)),
        Entry(name: "kern.bootargs", mib: [1, 1005], value: .string("")),
        Entry(name: "hw.ephemeral_storage", mib: [6, 1012], value: .integer(0, size: 4)),
        Entry(name: "hw.perflevel0.logicalcpu", mib: [6, 1013], value: .integer(n, size: 4)),
        Entry(name: "hw.perflevel0.logicalcpu_max", mib: [6, 1014], value: .integer(n, size: 4)),
        Entry(name: "hw.perflevel0.physicalcpu", mib: [6, 1015], value: .integer(n, size: 4)),
        Entry(name: "hw.perflevel0.physicalcpu_max", mib: [6, 1016], value: .integer(n, size: 4)),
        ]
    }

    static func bootTime() -> [UInt8] {
        let t = Date().timeIntervalSince1970
        var b: [UInt8] = []
        b.appendLE(Int64(t))
        b.appendLE(Int32((t - t.rounded(.down)) * 1e6))
        b.appendLE(Int32(0))
        return b
    }

    static let optionalMIBBase: Int32 = 0x4000

    public init(entries: [Entry]) {
        self.entries = entries
        reindex()
    }

    private var byName: [String: Int] = [:]
    private var byMIB: [[Int32]: Int] = [:]

    private mutating func reindex() {
        byName = [:]
        byMIB = [:]
        for (i, e) in entries.enumerated() {
            if byName[e.name] == nil { byName[e.name] = i }
            if byMIB[e.mib] == nil { byMIB[e.mib] = i }
        }
    }

    public func lookup(name: String) -> Entry? {
        if let i = byName[name] { return entries[i] }
        if name.hasPrefix("hw.optional.") {
            var h: UInt32 = 2166136261
            for b in name.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
            return Entry(name: name, mib: [6, Self.optionalMIBBase + Int32(h & 0x3FFF)], value: .integer(0, size: 4))
        }
        return nil
    }

    public func lookup(mib: [Int32]) -> Entry? {
        if let i = byMIB[mib] { return entries[i] }
        if mib.count == 2, mib[0] == 6, mib[1] >= Self.optionalMIBBase, mib[1] < Self.optionalMIBBase + 0x4000 {
            return Entry(name: "hw.optional.(\(mib[1]))", mib: mib, value: .integer(0, size: 4))
        }
        return nil
    }
}
