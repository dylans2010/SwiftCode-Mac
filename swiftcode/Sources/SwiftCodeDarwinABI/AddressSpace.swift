import Foundation

public struct VMProtection: OptionSet, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let read = VMProtection(rawValue: 1)
    public static let write = VMProtection(rawValue: 2)
    public static let execute = VMProtection(rawValue: 4)
    public static let none: VMProtection = []
    public static let readWrite: VMProtection = [.read, .write]
    public static let readExecute: VMProtection = [.read, .execute]
    public static let all: VMProtection = [.read, .write, .execute]

    public var el0PageAttributes: PageAttributes {
        let r = contains(.read), w = contains(.write), x = contains(.execute)
        if !r && !w && !x { return PageAttributes(access: .el1ReadOnly) }
        return PageAttributes(access: w ? .el0ReadWrite : .el0ReadOnly, el0Execute: x)
    }

    public var description: String {
        (contains(.read) ? "r" : "-") + (contains(.write) ? "w" : "-") + (contains(.execute) ? "x" : "-")
    }
}

public protocol PhysicalBacking: AnyObject {
    func allocateAnonymous(size: UInt64) throws -> UInt64
    func mapFile(_ file: GuestFile, offset: UInt64, size: UInt64) throws -> UInt64
    func mapFileReadOnly(_ file: GuestFile, offset: UInt64, size: UInt64) throws -> UInt64?
    func release(gpa: UInt64, size: UInt64)
    func readPhysical(gpa: UInt64, count: Int) throws -> [UInt8]
    func writePhysical(gpa: UInt64, bytes: [UInt8]) throws
    func writePhysical(gpa: UInt64, from bytes: UnsafeRawBufferPointer) throws
    func mapShared(_ object: SharedMemoryObject) throws -> UInt64
}

extension PhysicalBacking {
    public func mapFileReadOnly(_ file: GuestFile, offset: UInt64, size: UInt64) throws -> UInt64? { nil }
    public func writePhysical(gpa: UInt64, from bytes: UnsafeRawBufferPointer) throws {
        try writePhysical(gpa: gpa, bytes: Array(bytes))
    }
}

public struct GuestRegion: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Backing: Equatable, Hashable, Sendable {
        case anonymous(gpa: UInt64)
        case file(path: String, offset: UInt64, gpa: UInt64)
        case shared(serial: UInt64, offset: UInt64, gpa: UInt64)
        case unbacked
    }

    public var va: UInt64
    public var size: UInt64
    public var protection: VMProtection
    public var backing: Backing
    public var permanent: Bool

    public var end: UInt64 { va + size }

    public var gpa: UInt64 {
        switch backing {
        case let .anonymous(gpa), let .file(_, _, gpa), let .shared(_, _, gpa): gpa
        case .unbacked: 0
        }
    }

    public var backingDescription: String {
        switch backing {
        case let .anonymous(gpa): "anonymous gpa \(hex(gpa))"
        case let .file(path, offset, gpa): "\(path) @\(hex(offset)) gpa \(hex(gpa))"
        case let .shared(serial, offset, gpa): "shared object #\(serial) @\(hex(offset)) gpa \(hex(gpa))"
        case .unbacked: "anonymous, backed on first touch"
        }
    }

    public var description: String {
        "\(hex16(va))-\(hex16(end)) \(protection) \(backingDescription)\(permanent ? " permanent" : "")"
    }
}

public protocol GuestVirtualMemory: GuestMemoryAccess, AnyObject {
    func mapAnonymous(at: UInt64?, size: UInt64, protection: VMProtection, hint: UInt64?) throws -> UInt64
    func mapFile(_ file: GuestFile, offset: UInt64, at: UInt64?, size: UInt64, protection: VMProtection, hint: UInt64?) throws -> UInt64
    func unmap(va: UInt64, size: UInt64) throws
    func protect(va: UInt64, size: UInt64, protection: VMProtection) throws
    func mapShared(_ object: SharedMemoryObject, offset: UInt64, at: UInt64?, size: UInt64, protection: VMProtection,
                   hint: UInt64?) throws -> UInt64
    func share(va: UInt64, size: UInt64) throws -> (object: SharedMemoryObject, offset: UInt64)
    var regions: [GuestRegion] { get }
    func region(containing va: UInt64) -> GuestRegion?
    func regions(overlapping range: Range<UInt64>) -> [GuestRegion]
    var generation: UInt64 { get }
    var tlbGeneration: UInt64 { get }
    func tlbRange(since: UInt64) -> TLBRange?
    func resolveTranslationFault(va: UInt64) -> Bool
    func atomically<T>(_ body: () throws -> T) rethrows -> T
}

extension GuestVirtualMemory {
    public func atomically<T>(_ body: () throws -> T) rethrows -> T { try body() }

    public func resolveTranslationFault(va: UInt64) -> Bool { false }

    public var tlbGeneration: UInt64 { generation }
    public func tlbRange(since: UInt64) -> TLBRange? { nil }

    public func region(containing va: UInt64) -> GuestRegion? {
        regions.first { $0.va <= va && va < $0.end }
    }

    public func regions(overlapping range: Range<UInt64>) -> [GuestRegion] {
        regions.filter { $0.va < range.upperBound && range.lowerBound < $0.end }
    }
}

public final class GuestAddressSpace: GuestVirtualMemory {
    private struct Chunk: IntervalMapElement {
        var va: UInt64
        var size: UInt64
        var protection: VMProtection
        var gpa: UInt64
        var file: GuestFile?
        var fileOffset: UInt64
        var shared: SharedMemoryObject?
        var permanent: Bool
        var readOnlyShared: Bool = false
        var lazy: Bool = false
        var end: UInt64 { va + size }
        var start: UInt64 { va }

        func slice(_ lo: UInt64, _ hi: UInt64) -> Chunk {
            let start = max(lo, va), stop = min(hi, end)
            var c = self
            c.va = start
            c.size = stop - start
            c.gpa = lazy ? 0 : gpa + (start - va)
            c.fileOffset = fileOffset + (start - va)
            return c
        }

        var isAnonymous: Bool { file == nil && shared == nil }
        var isReleasable: Bool { shared == nil && !readOnlyShared && !lazy }
    }

    public let backing: any PhysicalBacking
    public let pageTables: GuestPageTables
    public private(set) var generation: UInt64 = 0
    public private(set) var tlbGeneration: UInt64 = 0
    private var writtenInvalidations: UInt64 = 0
    private var lastInvalidatedSpan: Range<UInt64>?
    nonisolated(unsafe) public static var flushOnAdditions = getenv("SWIFTCODE_TLB_FLUSH_ADDS").map { String(cString: $0) == "1" } ?? false
    public var requireEL0Access: Bool
    public private(set) var privatizedPages: UInt64 = 0

    public let anywhereExclusions: [Range<UInt64>] = [
        VMLayout.sharedRegionBase..<VMLayout.sharedRegionEnd,
        VMLayout.commpageReservationBase..<VMLayout.commpageReservationEnd,
    ]
    private let sortedExclusions: [Range<UInt64>]

    public let mutex = RecursiveMutex(name: "address space (L1)")
    private let chunks = IntervalMap<Chunk>()
    private var readOnlySharedChunks = 0
    private var regionsCache: [GuestRegion]?
    public private(set) var isDiscarded = false

    public init(backing: any PhysicalBacking, pageTables: PageTableBuilder = .stage3(), requireEL0Access: Bool = true) {
        self.backing = backing
        self.pageTables = GuestPageTables(pageTables)
        self.requireEL0Access = requireEL0Access
        sortedExclusions = anywhereExclusions.sorted { $0.lowerBound < $1.lowerBound }
    }

    private func region(of c: Chunk) -> GuestRegion {
        let backing: GuestRegion.Backing
        if let object = c.shared {
            backing = .shared(serial: object.serial, offset: c.fileOffset, gpa: c.gpa)
        } else if let file = c.file {
            backing = .file(path: file.guestPath, offset: c.fileOffset, gpa: c.gpa)
        } else if c.lazy {
            backing = .unbacked
        } else {
            backing = .anonymous(gpa: c.gpa)
        }
        return GuestRegion(va: c.va, size: c.size, protection: c.protection, backing: backing, permanent: c.permanent)
    }

    public var regions: [GuestRegion] { mutex.withLock { regionsLocked } }

    private var regionsLocked: [GuestRegion] {
        if let cached = regionsCache { return cached }
        let list = chunks.elements.map(region(of:))
        regionsCache = list
        return list
    }

    public func region(containing va: UInt64) -> GuestRegion? {
        mutex.withLock { chunks.element(containing: va).map(region(of:)) }
    }

    public func regions(overlapping range: Range<UInt64>) -> [GuestRegion] {
        mutex.withLock { chunks.overlapping(range.lowerBound, range.upperBound).map(region(of:)) }
    }

    public var regionCount: Int { mutex.withLock { chunks.count } }

    public func file(at va: UInt64) -> GuestFile? {
        mutex.withLock { chunks.element(containing: va)?.file }
    }

    public func sharedObject(at va: UInt64) -> SharedMemoryObject? {
        mutex.withLock { chunks.element(containing: va)?.shared }
    }

    public func mapAnonymous(at: UInt64?, size: UInt64, protection: VMProtection, hint: UInt64?) throws -> UInt64 {
        try map(file: nil, offset: 0, at: at, size: size, protection: protection, hint: hint, permanent: false)
    }

    public func mapFile(_ file: GuestFile, offset: UInt64, at: UInt64?, size: UInt64, protection: VMProtection, hint: UInt64?) throws -> UInt64 {
        try map(file: file, offset: offset, at: at, size: size, protection: protection, hint: hint, permanent: false)
    }

    public func mapShared(_ object: SharedMemoryObject, offset: UInt64, at: UInt64?, size: UInt64, protection: VMProtection,
                          hint: UInt64?) throws -> UInt64 {
        let rounded = (size + Self.pageMask) & ~Self.pageMask
        guard size > 0, offset & Self.pageMask == 0, offset <= object.size, rounded <= object.size - offset else {
            throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
        }
        return try map(file: nil, shared: object, offset: offset, at: at, size: size, protection: protection, hint: hint,
                       permanent: false)
    }

    public func share(va: UInt64, size: UInt64) throws -> (object: SharedMemoryObject, offset: UInt64) {
        try mutex.withLock { try shareLocked(va: va, size: size) }
    }

    public func atomically<T>(_ body: () throws -> T) rethrows -> T {
        try mutex.withLock(body)
    }

    private func shareLocked(va: UInt64, size: UInt64) throws -> (object: SharedMemoryObject, offset: UInt64) {
        try checkLive()
        let (lo, hi) = try checkedRange(va: va, size: size, permanent: false)
        let affected = chunks.overlapping(lo, hi)
        try checkCovered(affected, lo, hi)
        guard !affected.contains(where: \.permanent) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        if affected.count == 1, let object = affected[0].shared {
            return (object, affected[0].fileOffset + (lo - affected[0].va))
        }
        let object = try SharedMemoryObject(size: hi - lo)
        let gpa: UInt64
        do { gpa = try backing.mapShared(object) } catch { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
        var moved: [Chunk] = []
        for c in affected.map({ $0.slice(lo, hi) }) {
            if !c.lazy {
                let bytes = try backing.readPhysical(gpa: c.gpa, count: Int(c.size))
                object.write(offset: c.va - lo, bytes: bytes)
            }
            var n = c
            n.lazy = false
            n.gpa = gpa + (c.va - lo)
            n.file = nil
            n.shared = object
            n.fileOffset = c.va - lo
            n.readOnlyShared = false
            moved.append(n)
        }
        do {
            try pageTables.unmap(va: lo, size: hi - lo)
            for c in moved { try pageTables.map(va: c.va, pa: c.gpa, size: c.size, attributes: c.protection.el0PageAttributes) }
        } catch {
            throw mapPageTableError(error)
        }
        releaseAnonymous(affected, lo: lo, hi: hi)
        replaceChunks(lo, hi, with: moved)
        try commit()
        return (object, 0)
    }

    @discardableResult
    public func mapPermanentAnonymous(at va: UInt64, size: UInt64, protection: VMProtection) throws -> UInt64 {
        try map(file: nil, offset: 0, at: va, size: size, protection: protection, hint: nil, permanent: true)
    }

    public func unmap(va: UInt64, size: UInt64) throws {
        try mutex.withLock { try unmapLocked(va: va, size: size) }
    }

    private func unmapLocked(va: UInt64, size: UInt64) throws {
        try checkLive()
        let (lo, hi) = try checkedRange(va: va, size: size, permanent: false)
        let affected = chunks.overlapping(lo, hi)
        guard !affected.isEmpty else { return }
        guard !affected.contains(where: \.permanent) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        do { try pageTables.unmap(va: lo, size: hi - lo) } catch { throw mapPageTableError(error) }
        releaseAnonymous(affected, lo: lo, hi: hi)
        replaceChunks(lo, hi, with: [])
        try commit()
    }

    public func protect(va: UInt64, size: UInt64, protection: VMProtection) throws {
        try mutex.withLock { try protectLocked(va: va, size: size, protection: protection) }
    }

    private func protectLocked(va: UInt64, size: UInt64, protection: VMProtection) throws {
        try checkLive()
        let (lo, hi) = try checkedRange(va: va, size: size, permanent: false)
        var affected = chunks.overlapping(lo, hi)
        try checkCovered(affected, lo, hi)
        guard !affected.contains(where: \.permanent) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        if protection.contains(.write), affected.contains(where: \.readOnlyShared) {
            try privatize(lo, hi)
            affected = chunks.overlapping(lo, hi)
        }
        do {
            if affected.contains(where: \.lazy) {
                for c in affected where !c.lazy {
                    let s = c.slice(lo, hi)
                    try pageTables.protect(va: s.va, size: s.size, attributes: protection.el0PageAttributes)
                }
            } else {
                try pageTables.protect(va: lo, size: hi - lo, attributes: protection.el0PageAttributes)
            }
        } catch {
            throw mapPageTableError(error)
        }
        replaceChunks(lo, hi, with: affected.map { c in
            var s = c.slice(lo, hi)
            s.protection = protection
            return s
        })
        try commit()
    }

    public func discardAll() {
        mutex.withLock {
            isDiscarded = true
            chunks.removeAll()
            readOnlySharedChunks = 0
            regionsCache = []
        }
    }

    public func read(va: UInt64, count: Int) throws -> [UInt8] {
        try read(va: va, count: count, checkingEL0Access: requireEL0Access)
    }

    public func write(va: UInt64, bytes: [UInt8]) throws {
        try write(va: va, bytes: bytes, checkingEL0Access: requireEL0Access)
    }

    private func physicalPieces(va: UInt64, count: Int, write: Bool, checkingEL0Access: Bool) throws -> [(pa: UInt64, count: Int)] {
        guard count >= 0, UInt64(count) <= UInt64.max - va else { throw GuestMemoryError.badRange(va: va, count: count) }
        var pieces: [(pa: UInt64, count: Int)] = []
        var cursor = va & VMLayout.addressWithoutTag
        if isDiscarded, count > 0 { throw GuestMemoryError.unmapped(va: cursor) }
        var remaining = UInt64(count)
        while remaining > 0 {
            if pageTables.translate(cursor) == nil { _ = materializeLocked(va: cursor) }
            guard let (pa, attributes) = pageTables.translate(cursor) else { throw GuestMemoryError.unmapped(va: cursor) }
            if checkingEL0Access {
                let ok = write ? attributes.access.isEL0Writable : attributes.access.isEL0Readable
                guard ok else { throw GuestMemoryError.accessDenied(va: cursor) }
            }
            let inPage = VMLayout.pageSize - (cursor & (VMLayout.pageSize - 1))
            let n = min(inPage, remaining)
            pieces.append((pa, Int(n)))
            cursor += n
            remaining -= n
        }
        return pieces
    }

    public func read(va: UInt64, count: Int, checkingEL0Access: Bool) throws -> [UInt8] {
        try mutex.withLock { try readLocked(va: va, count: count, checkingEL0Access: checkingEL0Access) }
    }

    private func readLocked(va: UInt64, count: Int, checkingEL0Access: Bool) throws -> [UInt8] {
        let pieces = try physicalPieces(va: va, count: count, write: false, checkingEL0Access: checkingEL0Access)
        if pieces.count == 1 { return try backing.readPhysical(gpa: pieces[0].pa, count: pieces[0].count) }
        var out: [UInt8] = []
        out.reserveCapacity(max(0, count))
        for piece in pieces { out += try backing.readPhysical(gpa: piece.pa, count: piece.count) }
        return out
    }

    public func write(va: UInt64, bytes: [UInt8], checkingEL0Access: Bool) throws {
        try mutex.withLock { try writeLocked(va: va, bytes: bytes, checkingEL0Access: checkingEL0Access) }
    }

    private func writeLocked(va: UInt64, bytes: [UInt8], checkingEL0Access: Bool) throws {
        if !checkingEL0Access, readOnlySharedChunks > 0, !bytes.isEmpty, !isDiscarded {
            let start = va & VMLayout.addressWithoutTag
            if UInt64(bytes.count) <= UInt64.max - start {
                let lo = start & ~Self.pageMask
                let end = start + UInt64(bytes.count)
                let hi = end > UInt64.max - Self.pageMask ? UInt64.max & ~Self.pageMask : (end + Self.pageMask) & ~Self.pageMask
                if chunks.overlapping(lo, hi).contains(where: \.readOnlyShared) {
                    try privatize(lo, hi)
                    try commit()
                }
            }
        }
        let pieces = try physicalPieces(va: va, count: bytes.count, write: true, checkingEL0Access: checkingEL0Access)
        var offset = 0
        try bytes.withUnsafeBytes { raw in
            for piece in pieces {
                try backing.writePhysical(gpa: piece.pa, from: UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + piece.count)]))
                offset += piece.count
            }
        }
    }

    public func readCString(va: UInt64, maxLength: Int = DarwinFileSystem.maxPathLength) throws -> String {
        var out: [UInt8] = []
        var cursor = va
        while out.count < maxLength {
            let inPage = Int(VMLayout.pageSize - (cursor & (VMLayout.pageSize - 1)))
            let chunk = try read(va: cursor, count: min(inPage, maxLength - out.count))
            if let nul = chunk.firstIndex(of: 0) {
                out += chunk[..<nul]
                return String(decoding: out, as: UTF8.self)
            }
            out += chunk
            cursor += UInt64(chunk.count)
        }
        throw DarwinErrnoError(DarwinErrnoCode.ENAMETOOLONG)
    }

    public func flushPageTables() throws {
        try mutex.withLock { try flushLocked() }
    }

    private func flushLocked() throws {
        guard pageTables.hasDirtyTables else { return }
        generation &+= 1
        let invalidations = pageTables.invalidatingChanges
        let span = pageTables.takeInvalidatedSpan()
        if Self.flushOnAdditions || invalidations != writtenInvalidations {
            tlbGeneration &+= 1
            writtenInvalidations = invalidations
            lastInvalidatedSpan = Self.flushOnAdditions ? nil : span
        }
        let backing = self.backing
        try pageTables.writeDirtyTables { gpa, bytes in try backing.writePhysical(gpa: gpa, from: bytes) }
    }

    public func tlbRange(since: UInt64) -> TLBRange? {
        mutex.withLock {
            guard tlbGeneration == since &+ 1, let span = lastInvalidatedSpan else { return nil }
            return TLBRange(va: span.lowerBound, pages: (span.upperBound - span.lowerBound) >> VMLayout.pageShift)
        }
    }

    public static let lazyAnonymousThreshold: UInt64 = {
        if let v = getenv("SWIFTCODE_LAZY_ANON_MB"), let mb = UInt64(String(cString: v)) {
            return mb == 0 ? UInt64.max : mb << 20
        }
        return 256 << 20
    }()
    public static let lazyBlockSize: UInt64 = 256 << 10
    public private(set) var lazyBlocksMaterialized: UInt64 = 0

    public func resolveTranslationFault(va: UInt64) -> Bool {
        mutex.withLock {
            guard !isDiscarded else { return false }
            let page = va & VMLayout.addressWithoutTag
            guard pageTables.translate(page) == nil else { return false }
            return materializeLocked(va: page)
        }
    }

    private func materializeLocked(va: UInt64) -> Bool {
        guard !isDiscarded, let c = chunks.element(containing: va), c.lazy, c.protection != .none else { return false }
        let block = Self.lazyBlockSize
        let lo = max(c.va, va & ~(block - 1))
        let hi = min(c.end, (va & ~(block - 1)) + block)
        let size = hi - lo
        let gpa: UInt64
        do { gpa = try backing.allocateAnonymous(size: size) } catch {
            MapFailureLog.note("backing for a touched lazy block of 0x\(String(size, radix: 16)) bytes at 0x\(String(lo, radix: 16)): \(error)")
            return false
        }
        do {
            try pageTables.map(va: lo, pa: gpa, size: size, attributes: c.protection.el0PageAttributes)
        } catch {
            backing.release(gpa: gpa, size: size)
            MapFailureLog.note("page tables for a touched lazy block at 0x\(String(lo, radix: 16)): \(error)")
            return false
        }
        var b = c.slice(lo, hi)
        b.lazy = false
        b.gpa = gpa
        replaceChunks(lo, hi, with: [b])
        lazyBlocksMaterialized += 1
        do { try commit() } catch { return false }
        return true
    }

    private static let pageMask = VMLayout.pageSize - 1

    private func checkLive() throws {
        if isDiscarded { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
    }

    private func checkedRange(va: UInt64, size: UInt64, permanent: Bool) throws -> (UInt64, UInt64) {
        guard va & Self.pageMask == 0, size > 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        guard size <= UInt64.max - Self.pageMask else { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
        let rounded = (size + Self.pageMask) & ~Self.pageMask
        let limit = permanent ? UInt64(1) << VMLayout.virtualAddressBits : VMLayout.userVALimit
        guard va >= VMLayout.userVAFloor, va < limit, rounded <= limit - va else {
            throw DarwinErrnoError(DarwinErrnoCode.ENOMEM)
        }
        return (va, va + rounded)
    }

    private func checkCovered(_ affected: [Chunk], _ lo: UInt64, _ hi: UInt64) throws {
        var cursor = lo
        for c in affected {
            guard c.va <= cursor else { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
            cursor = max(cursor, c.end)
        }
        guard cursor >= hi else { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
    }

    private func map(file: GuestFile?, shared: SharedMemoryObject? = nil, offset: UInt64, at: UInt64?, size: UInt64,
                     protection: VMProtection, hint: UInt64?, permanent: Bool) throws -> UInt64 {
        try mutex.withLock {
            try mapLocked(file: file, shared: shared, offset: offset, at: at, size: size, protection: protection, hint: hint,
                          permanent: permanent)
        }
    }

    private func mapLocked(file: GuestFile?, shared: SharedMemoryObject? = nil, offset: UInt64, at: UInt64?, size: UInt64,
                           protection: VMProtection, hint: UInt64?, permanent: Bool) throws -> UInt64 {
        try checkLive()
        guard size > 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        guard offset & Self.pageMask == 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        guard size <= UInt64.max - Self.pageMask else { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
        let rounded = (size + Self.pageMask) & ~Self.pageMask
        guard offset <= UInt64.max - rounded else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }

        let lo: UInt64, hi: UInt64
        if let at {
            (lo, hi) = try checkedRange(va: at, size: rounded, permanent: permanent)
        } else {
            lo = try findFree(size: rounded, hint: hint)
            hi = lo + rounded
        }
        let replaced = chunks.overlapping(lo, hi)
        guard !replaced.contains(where: \.permanent) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        if file == nil, shared == nil, !permanent, rounded >= Self.lazyAnonymousThreshold {
            if !replaced.isEmpty { do { try pageTables.unmap(va: lo, size: rounded) } catch { throw mapPageTableError(error) } }
            releaseAnonymous(replaced, lo: lo, hi: hi)
            replaceChunks(lo, hi, with: [Chunk(va: lo, size: rounded, protection: protection, gpa: 0, file: nil,
                                               fileOffset: 0, shared: nil, permanent: false, lazy: true)])
            try commit()
            return lo
        }
        do { try pageTables.checkCapacity(va: lo, size: rounded) } catch {
            MapFailureLog.note("page tables for 0x\(String(rounded, radix: 16)) bytes at 0x\(String(lo, radix: 16)): \(error)")
            throw mapPageTableError(error)
        }

        var readOnlyShared = false
        let gpa: UInt64
        do {
            if let shared {
                gpa = try backing.mapShared(shared) + offset
            } else if let file {
                if !protection.contains(.write), let view = try backing.mapFileReadOnly(file, offset: offset, size: rounded) {
                    gpa = view
                    readOnlyShared = true
                } else {
                    gpa = try backing.mapFile(file, offset: offset, size: rounded)
                }
            } else {
                gpa = try backing.allocateAnonymous(size: rounded)
            }
        } catch let e as DarwinErrnoError {
            MapFailureLog.note("backing for 0x\(String(rounded, radix: 16)) bytes (\(file?.guestPath ?? (shared != nil ? "shared" : "anonymous"))): \(e)")
            throw e
        } catch {
            MapFailureLog.note("backing for 0x\(String(rounded, radix: 16)) bytes (\(file?.guestPath ?? (shared != nil ? "shared" : "anonymous"))): \(error)")
            throw DarwinErrnoError(DarwinErrnoCode.ENOMEM)
        }

        do {
            guard gpa < 1 << VMLayout.physicalAddressBits, rounded <= (1 << VMLayout.physicalAddressBits) - gpa else {
                throw PageTableError.physicalAddressOutOfRange(pa: gpa, size: rounded)
            }
            if !replaced.isEmpty { try pageTables.unmap(va: lo, size: rounded) }
            try pageTables.map(va: lo, pa: gpa, size: rounded, attributes: protection.el0PageAttributes)
        } catch {
            if shared == nil && !readOnlyShared { backing.release(gpa: gpa, size: rounded) }
            throw mapPageTableError(error)
        }
        releaseAnonymous(replaced, lo: lo, hi: hi)
        replaceChunks(lo, hi, with: [Chunk(va: lo, size: rounded, protection: protection, gpa: gpa, file: file,
                                           fileOffset: offset, shared: shared, permanent: permanent,
                                           readOnlyShared: readOnlyShared)])
        try commit()
        return lo
    }

    private func privatize(_ lo: UInt64, _ hi: UInt64) throws {
        for c in chunks.overlapping(lo, hi) where c.readOnlyShared {
            var s = c.slice(lo, hi)
            guard let file = s.file else { continue }
            let gpa: UInt64
            do { gpa = try backing.mapFile(file, offset: s.fileOffset, size: s.size) } catch let e as DarwinErrnoError {
                throw e
            } catch {
                throw DarwinErrnoError(DarwinErrnoCode.ENOMEM)
            }
            do {
                try pageTables.unmap(va: s.va, size: s.size)
                try pageTables.map(va: s.va, pa: gpa, size: s.size, attributes: s.protection.el0PageAttributes)
            } catch {
                throw mapPageTableError(error)
            }
            s.gpa = gpa
            s.readOnlyShared = false
            replaceChunks(s.va, s.end, with: [s])
            privatizedPages += s.size / VMLayout.pageSize
        }
    }

    private func replaceChunks(_ lo: UInt64, _ hi: UInt64, with inside: [Chunk]) {
        for c in chunks.extract(lo, hi) {
            if c.readOnlyShared { readOnlySharedChunks -= 1 }
            if c.va < lo { insertChunk(c.slice(c.va, lo)) }
            if c.end > hi { insertChunk(c.slice(hi, c.end)) }
        }
        for c in inside { insertChunk(c) }
        regionsCache = nil
    }

    private func insertChunk(_ c: Chunk) {
        if c.readOnlyShared { readOnlySharedChunks += 1 }
        chunks.insert(c)
    }

    private func findFree(size: UInt64, hint: UInt64?) throws -> UInt64 {
        let base = VMLayout.anonymousVABase
        var start = max(hint ?? base, base)
        if start > UInt64.max - Self.pageMask { start = VMLayout.userVALimit }
        start = (start + Self.pageMask) & ~Self.pageMask
        if let va = firstFit(size: size, from: start) { return va }
        if start > base, let va = firstFit(size: size, from: base) { return va }
        throw DarwinErrnoError(DarwinErrnoCode.ENOMEM)
    }

    private func firstFit(size: UInt64, from start: UInt64) -> UInt64? {
        let limit = VMLayout.userVALimit
        var a = start
        for ex in sortedExclusions + [limit..<limit] {
            guard a < limit else { return nil }
            if ex.upperBound <= a && ex.lowerBound < limit { continue }
            let b = min(ex.lowerBound, limit)
            if b > a, let p = chunks.firstGap(from: a, size: size), p < b, size <= b - p { return p }
            a = max(a, ex.upperBound)
        }
        return nil
    }

    private func releaseAnonymous(_ affected: [Chunk], lo: UInt64, hi: UInt64) {
        for c in affected where c.isReleasable {
            let s = c.slice(lo, hi)
            backing.release(gpa: s.gpa, size: s.size)
        }
    }

    private func commit() throws {
        try flushLocked()
    }

    private func mapPageTableError(_ error: Error) -> Error {
        guard let e = error as? PageTableError else { return error }
        switch e {
        case .arenaExhausted: return DarwinErrnoError(DarwinErrnoCode.ENOMEM)
        case .notMapped: return DarwinErrnoError(DarwinErrnoCode.ENOMEM)
        case .virtualAddressOutOfRange, .physicalAddressOutOfRange: return DarwinErrnoError(DarwinErrnoCode.ENOMEM)
        case .unaligned, .emptyRange, .alreadyMapped: return DarwinErrnoError(DarwinErrnoCode.EINVAL)
        }
    }
}

public enum MapFailureLog {
    nonisolated(unsafe) private static var count = 0
    private static let lock = NSLock()
    public static let limit = 40
    static func note(_ text: String) {
        lock.lock(); count += 1; let n = count; lock.unlock()
        guard n <= limit else { return }
        FileHandle.standardError.write(("swiftcode-simd: guest mapping failed: " + text + (n == limit ? " (further failures not shown)" : "") + "\n").data(using: .utf8)!)
    }
}

public struct FakePhysicalBackingError: Error, Equatable, Sendable, CustomStringConvertible {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}

public final class FakePhysicalBacking: PhysicalBacking {
    public struct FileSlot: Equatable, Sendable {
        public var gpa: UInt64
        public var size: UInt64
        public var path: String
        public var offset: UInt64
    }

    public let ramGPA: UInt64
    public let ramSize: UInt64
    public let anonymousPoolGPA: UInt64
    public let anonymousPoolSize: UInt64
    public let fileSlotGPABase: UInt64
    public let sharedReadOnlyFiles: Bool

    private var pages: [UInt64: [UInt8]] = [:]
    private let pool: RangeAllocator
    public var anonymousBytesInUse: UInt64 { pool.bytesInUse }
    private var nextFileSlotGPA: UInt64
    public private(set) var fileSlots: [FileSlot] = []
    private var readOnlyViews: [String: (gpa: UInt64, span: UInt64)] = [:]
    private let readOnlyRanges = IntervalMap<PlainInterval>()
    public private(set) var readOnlyViewRequests = 0
    private var sharedSlots: [(gpa: UInt64, object: SharedMemoryObject)] = []
    public var writeLog: [(gpa: UInt64, count: Int)] = []

    public init(ramGPA: UInt64 = VMLayout.ramGPA, ramSize: UInt64 = VMLayout.stage3RAMSize,
                anonymousPoolGPA: UInt64 = VMLayout.anonymousPoolGPA, anonymousPoolSize: UInt64 = VMLayout.anonymousPoolSize,
                fileSlotGPABase: UInt64 = VMLayout.fileSlotGPABase, sharedReadOnlyFiles: Bool = false) {
        self.ramGPA = ramGPA
        self.ramSize = ramSize
        self.anonymousPoolGPA = anonymousPoolGPA
        self.anonymousPoolSize = anonymousPoolSize
        self.fileSlotGPABase = fileSlotGPABase
        self.sharedReadOnlyFiles = sharedReadOnlyFiles
        self.nextFileSlotGPA = fileSlotGPABase
        self.pool = RangeAllocator(base: anonymousPoolGPA, size: anonymousPoolSize)
    }

    public func allocateAnonymous(size: UInt64) throws -> UInt64 {
        guard size > 0, VMLayout.isPageAligned(size) else { throw FakePhysicalBackingError("bad anonymous size \(hex(size))") }
        guard let gpa = pool.allocate(size) else { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
        return gpa
    }

    private func fill(gpa: UInt64, file: GuestFile, offset: UInt64, size: UInt64) throws {
        let page = VMLayout.pageSize
        var o: UInt64 = 0
        while o < size {
            let bytes = try file.read(count: Int(page), offset: offset + o)
            if bytes.contains(where: { $0 != 0 }) {
                pages[gpa + o] = bytes + [UInt8](repeating: 0, count: Int(page) - bytes.count)
            }
            if bytes.count < Int(page) { break }
            o += page
        }
    }

    public func mapFile(_ file: GuestFile, offset: UInt64, size: UInt64) throws -> UInt64 {
        guard size > 0, VMLayout.isPageAligned(size), VMLayout.isPageAligned(offset) else {
            throw FakePhysicalBackingError("bad file mapping offset \(hex(offset)) size \(hex(size))")
        }
        let gpa = nextFileSlotGPA
        nextFileSlotGPA += size
        try fill(gpa: gpa, file: file, offset: offset, size: size)
        fileSlots.append(FileSlot(gpa: gpa, size: size, path: file.guestPath, offset: offset))
        return gpa
    }

    public func mapFileReadOnly(_ file: GuestFile, offset: UInt64, size: UInt64) throws -> UInt64? {
        guard sharedReadOnlyFiles else { return nil }
        guard size > 0, VMLayout.isPageAligned(size), VMLayout.isPageAligned(offset) else {
            throw FakePhysicalBackingError("bad file mapping offset \(hex(offset)) size \(hex(size))")
        }
        let key = "\(file.hostPath)#\(file.size)"
        let view: (gpa: UInt64, span: UInt64)
        if let v = readOnlyViews[key] {
            view = v
        } else {
            let span = (file.size + VMLayout.pageSize - 1) & ~(VMLayout.pageSize - 1)
            guard span > 0 else { return nil }
            view = (nextFileSlotGPA, span)
            nextFileSlotGPA += span
            try fill(gpa: view.gpa, file: file, offset: 0, size: span)
            readOnlyViews[key] = view
            readOnlyRanges.insert(PlainInterval(start: view.gpa, end: view.gpa + span))
        }
        guard offset <= view.span, size <= view.span - offset else { return nil }
        readOnlyViewRequests += 1
        return view.gpa + offset
    }

    public func mapShared(_ object: SharedMemoryObject) throws -> UInt64 {
        if let slot = sharedSlots.first(where: { $0.object === object }) { return slot.gpa }
        let gpa = nextFileSlotGPA
        nextFileSlotGPA += object.size
        sharedSlots.append((gpa, object))
        return gpa
    }

    private func sharedSlot(_ gpa: UInt64) -> (gpa: UInt64, object: SharedMemoryObject)? {
        sharedSlots.first { gpa >= $0.gpa && gpa - $0.gpa < $0.object.size }
    }

    public private(set) var releaseViolations: [String] = []

    public func release(gpa: UInt64, size: UInt64) {
        guard size > 0 else { return }
        if gpa >= anonymousPoolGPA, gpa - anonymousPoolGPA < anonymousPoolSize, !pool.isAllocated(gpa, size) {
            releaseViolations.append("release of \(hex(gpa))+\(hex(size)), not entirely allocated")
        }
        for r in pool.free(gpa, size) {
            var p = r.lowerBound
            while p < r.upperBound {
                pages[p] = nil
                p += VMLayout.pageSize
            }
        }
    }

    private func isBacked(_ gpa: UInt64) -> Bool {
        if gpa >= ramGPA && gpa - ramGPA < ramSize { return true }
        if gpa >= anonymousPoolGPA && gpa - anonymousPoolGPA < anonymousPoolSize { return true }
        return gpa >= fileSlotGPABase && gpa < nextFileSlotGPA
    }

    public func readPhysical(gpa: UInt64, count: Int) throws -> [UInt8] {
        guard count >= 0 else { throw FakePhysicalBackingError("negative read") }
        var out: [UInt8] = []
        out.reserveCapacity(count)
        var cursor = gpa
        var remaining = count
        while remaining > 0 {
            guard isBacked(cursor) else { throw FakePhysicalBackingError("gpa \(hex(cursor)) is not backed") }
            let base = cursor & ~(VMLayout.pageSize - 1)
            let inPage = Int(cursor - base)
            let n = min(remaining, Int(VMLayout.pageSize) - inPage)
            if let slot = sharedSlot(cursor) {
                out += slot.object.read(offset: cursor - slot.gpa, count: n)
            } else if let page = pages[base] { out += page[inPage..<(inPage + n)] } else { out += repeatElement(0, count: n) }
            cursor += UInt64(n)
            remaining -= n
        }
        return out
    }

    public func writePhysical(gpa: UInt64, bytes: [UInt8]) throws {
        if !bytes.isEmpty, readOnlyRanges.intersects(gpa, gpa + UInt64(bytes.count)) {
            throw FakePhysicalBackingError("write to read-only file memory at gpa \(hex(gpa))")
        }
        var cursor = gpa
        var offset = 0
        while offset < bytes.count {
            guard isBacked(cursor) else { throw FakePhysicalBackingError("gpa \(hex(cursor)) is not backed") }
            let base = cursor & ~(VMLayout.pageSize - 1)
            let inPage = Int(cursor - base)
            let n = min(bytes.count - offset, Int(VMLayout.pageSize) - inPage)
            if let slot = sharedSlot(cursor) {
                slot.object.write(offset: cursor - slot.gpa, bytes: Array(bytes[offset..<(offset + n)]))
                cursor += UInt64(n)
                offset += n
                continue
            }
            var page = pages[base] ?? [UInt8](repeating: 0, count: Int(VMLayout.pageSize))
            page.replaceSubrange(inPage..<(inPage + n), with: bytes[offset..<(offset + n)])
            pages[base] = page
            cursor += UInt64(n)
            offset += n
        }
        writeLog.append((gpa, bytes.count))
    }
}
