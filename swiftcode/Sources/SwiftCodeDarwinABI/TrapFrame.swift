#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public struct TrapFrame: Equatable, Sendable, CustomStringConvertible {
    public static let byteCount = 320
    public static let registerCount = 31

    public enum Offset {
        public static let x0 = 0
        public static let spEL0 = 248
        public static let elr = 256
        public static let spsr = 264
        public static let esr = 272
        public static let far = 280
        public static let tpidrro = 288
        public static let tpidr = 296
        public static let kind = 304
        public static let resumeFlags = 312
        public static let reserved = resumeFlags
    }

    public enum ResumeFlag {
        public static let flushTLB: UInt64 = 1 << 0
        public static let fpTouch: UInt64 = 1 << 1
        public static let keepICache: UInt64 = 1 << 2
        public static let byVA: UInt64 = 1 << 3
        public static let maxPagesByVA: UInt64 = 256
    }

    public static let peelLevel: Int = getenv("SWIFTCODE_TRAP_PEEL").flatMap { Int(String(cString: $0)) } ?? 0
    public static let peelNumber: UInt64 = getenv("SWIFTCODE_TRAP_PEEL_NUMBER").flatMap { UInt64(String(cString: $0)) } ?? 39

    @inline(__always) public static func peels(at level: Int, x16: UInt64) -> Bool {
        peelLevel == level && x16 & 0xFFFF_FFFF == peelNumber
    }

    public mutating func answerPeeled() {
        x[0] = 1
        carry = false
    }

    public static let invalidateByVA = getenv("SWIFTCODE_TLB_BY_VA").map { String(cString: $0) != "0" } ?? true

    public mutating func requestTLBInvalidation(_ range: TLBRange?) {
        var packed: UInt64 = 0
        if Self.invalidateByVA, let r = range, r.pages >= 1, r.pages <= ResumeFlag.maxPagesByVA,
           r.va & (VMLayout.pageSize - 1) == 0, r.va >> 62 == 0 {
            packed = ResumeFlag.byVA | ((r.pages - 1) << 8) | ((r.va >> VMLayout.pageShift) << 16)
        }
        let field = ResumeFlag.byVA | 0xFFFF_FFFF_FFFF_FF00
        if flushTLB {
            if packed == 0 || resumeFlags & field != packed { resumeFlags &= ~field }
            return
        }
        flushTLB = true
        resumeFlags |= packed
    }

    public var tlbInvalidationRange: TLBRange? {
        guard flushTLB, resumeFlags & ResumeFlag.byVA != 0 else { return nil }
        return TLBRange(va: (resumeFlags >> 16) << VMLayout.pageShift, pages: ((resumeFlags >> 8) & 0xFF) + 1)
    }

    public enum Kind: UInt64, Sendable, CustomStringConvertible {
        case svc = 1
        case el0Synchronous = 2
        case asynchronous = 3
        case el1Synchronous = 4

        public var description: String {
            switch self {
            case .svc: "SVC from EL0"
            case .el0Synchronous: "synchronous exception from EL0"
            case .asynchronous: "IRQ/FIQ/SError"
            case .el1Synchronous: "synchronous exception at EL1"
            }
        }
    }

    public var x: TrapRegisters
    public var spEL0: UInt64
    public var elr: UInt64
    public var spsr: UInt64
    public var esr: UInt64
    public var far: UInt64
    public var tpidrro: UInt64
    public var tpidr: UInt64
    public var kind: UInt64
    public var resumeFlags: UInt64 = 0

    public init(
        x: [UInt64] = Array(repeating: 0, count: TrapFrame.registerCount),
        spEL0: UInt64 = 0, elr: UInt64 = 0, spsr: UInt64 = 0, esr: UInt64 = 0, far: UInt64 = 0,
        tpidrro: UInt64 = 0, tpidr: UInt64 = 0, kind: UInt64 = 0
    ) {
        self.x = TrapRegisters(x)
        self.spEL0 = spEL0
        self.elr = elr
        self.spsr = spsr
        self.esr = esr
        self.far = far
        self.tpidrro = tpidrro
        self.tpidr = tpidr
        self.kind = kind
    }

    public init(decoding bytes: [UInt8]) throws {
        guard bytes.count >= Self.byteCount else {
            throw DarwinABIError.truncated(what: "trap frame", expected: Self.byteCount, actual: bytes.count)
        }
        x = TrapRegisters()
        for i in 0..<Self.registerCount { x[i] = readLE(bytes, at: Offset.x0 + 8 * i) }
        spEL0 = readLE(bytes, at: Offset.spEL0)
        elr = readLE(bytes, at: Offset.elr)
        spsr = readLE(bytes, at: Offset.spsr)
        esr = readLE(bytes, at: Offset.esr)
        far = readLE(bytes, at: Offset.far)
        tpidrro = readLE(bytes, at: Offset.tpidrro)
        tpidr = readLE(bytes, at: Offset.tpidr)
        kind = readLE(bytes, at: Offset.kind)
    }

    public init(decodingFrameAt p: UnsafeRawPointer) {
        @inline(__always) func word(_ offset: Int) -> UInt64 { UInt64(littleEndian: p.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
        x = TrapRegisters(loadingFrom: p + Offset.x0)
        spEL0 = word(Offset.spEL0)
        elr = word(Offset.elr)
        spsr = word(Offset.spsr)
        esr = word(Offset.esr)
        far = word(Offset.far)
        tpidrro = word(Offset.tpidrro)
        tpidr = word(Offset.tpidr)
        kind = word(Offset.kind)
    }

    public func encode(into p: UnsafeMutableRawPointer) {
        @inline(__always) func put(_ v: UInt64, _ offset: Int) { p.storeBytes(of: v.littleEndian, toByteOffset: offset, as: UInt64.self) }
        x.store(to: p + Offset.x0)
        put(spEL0, Offset.spEL0)
        put(elr, Offset.elr)
        put(spsr, Offset.spsr)
        put(esr, Offset.esr)
        put(far, Offset.far)
        put(tpidrro, Offset.tpidrro)
        put(tpidr, Offset.tpidr)
        put(kind, Offset.kind)
        put(resumeFlags, Offset.resumeFlags)
    }

    public func encoded() -> [UInt8] {
        var b: [UInt8] = []
        b.reserveCapacity(Self.byteCount)
        for i in 0..<Self.registerCount { appendLE(i < x.count ? x[i] : 0, to: &b) }
        for v in [spEL0, elr, spsr, esr, far, tpidrro, tpidr, kind, resumeFlags] { appendLE(v, to: &b) }
        return b
    }

    public var carry: Bool {
        get { spsr & AArch64.SPSR.c != 0 }
        set { spsr = newValue ? spsr | AArch64.SPSR.c : spsr & ~AArch64.SPSR.c }
    }

    public var flushTLB: Bool {
        get { resumeFlags & ResumeFlag.flushTLB != 0 }
        set {
            resumeFlags = newValue ? resumeFlags | ResumeFlag.flushTLB : resumeFlags & ~ResumeFlag.flushTLB
            resumeFlags &= ~(ResumeFlag.byVA | 0xFFFF_FFFF_FFFF_FF00)
        }
    }

    public var trapKind: Kind? { Kind(rawValue: kind) }
    public var syndrome: ExceptionSyndrome { ExceptionSyndrome(esr) }

    public var description: String {
        let kindText = trapKind.map(\.description) ?? "unknown kind \(kind)"
        var lines = ["\(kindText): \(syndrome) FAR=\(hex16(far)) ELR=\(hex16(elr))"]
        for row in stride(from: 0, to: Self.registerCount, by: 4) {
            lines.append((row..<min(row + 4, Self.registerCount)).map { i in
                let name = i < 10 ? " x\(i)" : "x\(i)"
                return "\(name)=\(hex16(i < x.count ? x[i] : 0))"
            }.joined(separator: " "))
        }
        lines.append(" sp=\(hex16(spEL0)) spsr=\(hex16(spsr)) tpidrro=\(hex16(tpidrro)) tpidr=\(hex16(tpidr))")
        return lines.joined(separator: "\n")
    }
}

public struct TrapRegisters: RandomAccessCollection, MutableCollection, Equatable, Sendable, ExpressibleByArrayLiteral,
    CustomStringConvertible {
    public typealias Element = UInt64
    public typealias Index = Int
    private var r: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                    UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                    UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                    UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64)
        = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    public init() {}
    public init<S: Sequence>(_ values: S) where S.Element == UInt64 {
        var i = 0
        for v in values {
            guard i < 31 else { break }
            self[i] = v
            i += 1
        }
    }
    public init(arrayLiteral elements: UInt64...) { self.init(elements) }

    @inline(__always) public init(loadingFrom p: UnsafeRawPointer) {
        withUnsafeMutableBytes(of: &r) { d in
            for i in 0..<31 { d.storeBytes(of: UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self)),
                                           toByteOffset: 8 * i, as: UInt64.self) }
        }
    }

    @inline(__always) public func store(to p: UnsafeMutableRawPointer) {
        withUnsafeBytes(of: r) { s in
            for i in 0..<31 { p.storeBytes(of: s.load(fromByteOffset: 8 * i, as: UInt64.self).littleEndian,
                                           toByteOffset: 8 * i, as: UInt64.self) }
        }
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { 31 }
    @inline(__always) public func index(after i: Int) -> Int { i + 1 }
    @inline(__always) public func index(before i: Int) -> Int { i - 1 }

    @inline(__always) public subscript(i: Int) -> UInt64 {
        get {
            precondition(i >= 0 && i < 31, "register index out of range")
            return withUnsafeBytes(of: r) { $0.load(fromByteOffset: 8 * i, as: UInt64.self) }
        }
        set {
            precondition(i >= 0 && i < 31, "register index out of range")
            withUnsafeMutableBytes(of: &r) { $0.storeBytes(of: newValue, toByteOffset: 8 * i, as: UInt64.self) }
        }
    }

    public static func == (a: TrapRegisters, b: TrapRegisters) -> Bool {
        withUnsafeBytes(of: a.r) { x in withUnsafeBytes(of: b.r) { y in x.elementsEqual(y) } }
    }

    public var description: String { Array(self).description }

    @inline(__always) public func prefixArray(_ n: Int) -> [UInt64] {
        precondition(n >= 0 && n <= 31)
        return withUnsafeBytes(of: r) { s in
            [UInt64](unsafeUninitializedCapacity: n) { b, count in
                for i in 0..<n { b[i] = s.load(fromByteOffset: 8 * i, as: UInt64.self) }
                count = n
            }
        }
    }
}

func hex16(_ v: UInt64) -> String {
    let s = String(v, radix: 16)
    return "0x" + String(repeating: "0", count: max(0, 16 - s.count)) + s
}

public enum ExceptionClass: UInt8, Sendable, CaseIterable, CustomStringConvertible {
    case unknown = 0x00
    case trappedWFIorWFE = 0x01
    case trappedSIMDorFP = 0x07
    case pointerAuthenticationTrap = 0x09
    case branchTarget = 0x0D
    case illegalExecutionState = 0x0E
    case svc = 0x15
    case hvc = 0x16
    case smc = 0x17
    case trappedSystemRegister = 0x18
    case trappedSVE = 0x19
    case pointerAuthenticationFailure = 0x1C
    case trappedSME = 0x1D
    case instructionAbortLowerEL = 0x20
    case instructionAbortSameEL = 0x21
    case pcAlignment = 0x22
    case dataAbortLowerEL = 0x24
    case dataAbortSameEL = 0x25
    case spAlignment = 0x26
    case floatingPoint = 0x2C
    case serror = 0x2F
    case breakpointLowerEL = 0x30
    case breakpointSameEL = 0x31
    case softwareStepLowerEL = 0x32
    case softwareStepSameEL = 0x33
    case watchpointLowerEL = 0x34
    case watchpointSameEL = 0x35
    case brk = 0x3C

    public var description: String {
        switch self {
        case .unknown: "unknown reason"
        case .trappedWFIorWFE: "trapped WFI/WFE"
        case .trappedSIMDorFP: "trapped SIMD/FP access"
        case .pointerAuthenticationTrap: "trapped pointer authentication instruction"
        case .branchTarget: "branch target exception"
        case .illegalExecutionState: "illegal execution state"
        case .svc: "SVC (AArch64)"
        case .hvc: "HVC (AArch64)"
        case .smc: "SMC (AArch64)"
        case .trappedSystemRegister: "trapped MSR/MRS/system instruction"
        case .trappedSVE: "trapped SVE access"
        case .trappedSME: "trapped SME access"
        case .pointerAuthenticationFailure: "pointer authentication failure"
        case .instructionAbortLowerEL: "instruction abort from a lower EL"
        case .instructionAbortSameEL: "instruction abort at the same EL"
        case .pcAlignment: "PC alignment fault"
        case .dataAbortLowerEL: "data abort from a lower EL"
        case .dataAbortSameEL: "data abort at the same EL"
        case .spAlignment: "SP alignment fault"
        case .floatingPoint: "floating-point exception (AArch64)"
        case .serror: "SError"
        case .breakpointLowerEL: "breakpoint from a lower EL"
        case .breakpointSameEL: "breakpoint at the same EL"
        case .softwareStepLowerEL: "software step from a lower EL"
        case .softwareStepSameEL: "software step at the same EL"
        case .watchpointLowerEL: "watchpoint from a lower EL"
        case .watchpointSameEL: "watchpoint at the same EL"
        case .brk: "BRK (AArch64)"
        }
    }

    public var isAbort: Bool {
        switch self {
        case .instructionAbortLowerEL, .instructionAbortSameEL, .dataAbortLowerEL, .dataAbortSameEL: true
        default: false
        }
    }

    public var isDataAbort: Bool { self == .dataAbortLowerEL || self == .dataAbortSameEL }
}

public struct ExceptionSyndrome: Equatable, Sendable, CustomStringConvertible {
    public var raw: UInt64

    public init(_ raw: UInt64) { self.raw = raw }

    public init(ec: UInt8, il: Bool = true, iss: UInt32 = 0) {
        raw = UInt64(ec & 0x3F) << 26 | (il ? 1 << 25 : 0) | UInt64(iss & 0x1FF_FFFF)
    }

    public var ec: UInt8 { UInt8((raw >> 26) & 0x3F) }
    public var il: Bool { raw & (1 << 25) != 0 }
    public var iss: UInt32 { UInt32(raw & 0x1FF_FFFF) }
    public var iss2: UInt32 { UInt32((raw >> 32) & 0xFF_FFFF) }

    public var exceptionClass: ExceptionClass? { ExceptionClass(rawValue: ec) }

    public var svcImmediate: UInt16? { exceptionClass == .svc ? UInt16(iss & 0xFFFF) : nil }

    public var faultStatusCode: UInt8? { exceptionClass?.isAbort == true ? UInt8(iss & 0x3F) : nil }

    public var isWrite: Bool? { exceptionClass?.isDataAbort == true ? iss & (1 << 6) != 0 : nil }

    public static func faultStatusName(_ fsc: UInt8) -> String {
        let level = fsc & 3
        switch fsc {
        case 0x00...0x03: return "address size fault, level \(level)"
        case 0x04...0x07: return "translation fault, level \(level)"
        case 0x08...0x0B: return "access flag fault, level \(level)"
        case 0x0C...0x0F: return "permission fault, level \(level)"
        case 0x10: return "synchronous external abort"
        case 0x21: return "alignment fault"
        case 0x30: return "TLB conflict abort"
        default: return "fault status \(hex(fsc))"
        }
    }

    public var description: String {
        let name = exceptionClass?.description ?? "unrecognized"
        var s = "EC=\(hex(ec)) (\(name)) IL=\(il ? 1 : 0) ISS=\(hex(iss))"
        if let fsc = faultStatusCode {
            s += " [\(Self.faultStatusName(fsc))"
            if let w = isWrite { s += w ? ", write" : ", read" }
            s += "]"
        }
        if let imm = svcImmediate { s += " [svc #\(hex(imm))]" }
        return s
    }
}

public struct TLBRange: Equatable, Sendable {
    public var va: UInt64
    public var pages: UInt64
    public init(va: UInt64, pages: UInt64) {
        self.va = va
        self.pages = pages
    }
}
