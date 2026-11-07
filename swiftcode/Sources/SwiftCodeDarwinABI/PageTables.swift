public struct PageAttributes: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Access: Equatable, Hashable, Sendable, CaseIterable {
        case el1ReadWrite
        case el1ReadOnly
        case el0ReadWrite
        case el0ReadOnly

        public var apBits: UInt64 {
            switch self {
            case .el1ReadWrite: 0b00
            case .el0ReadWrite: 0b01
            case .el1ReadOnly: 0b10
            case .el0ReadOnly: 0b11
            }
        }

        public init(apBits: UInt64) {
            switch apBits & 3 {
            case 0b00: self = .el1ReadWrite
            case 0b01: self = .el0ReadWrite
            case 0b10: self = .el1ReadOnly
            default: self = .el0ReadOnly
            }
        }

        public var isEL0Readable: Bool { self == .el0ReadWrite || self == .el0ReadOnly }
        public var isEL0Writable: Bool { self == .el0ReadWrite }
    }

    public var access: Access
    public var device: Bool
    public var el0Execute: Bool
    public var el1Execute: Bool

    public init(access: Access, device: Bool = false, el0Execute: Bool = false, el1Execute: Bool = false) {
        self.access = access
        self.device = device
        self.el0Execute = el0Execute
        self.el1Execute = el1Execute
    }

    public var leafDescriptorBits: UInt64 {
        typealias D = AArch64.Descriptor
        var bits = D.attrIndx(device ? AArch64.MAIR.deviceIndex : AArch64.MAIR.normalIndex)
            | D.ap(access.apBits)
            | D.sh(AArch64.TCR.shareabilityInner)
            | D.af
        if !el1Execute { bits |= D.pxn }
        if !el0Execute { bits |= D.uxn }
        return bits
    }

    public init(leafDescriptor d: UInt64) {
        access = Access(apBits: (d >> 6) & 3)
        device = (d >> 2) & 7 == AArch64.MAIR.deviceIndex
        el0Execute = d & AArch64.Descriptor.uxn == 0
        el1Execute = d & AArch64.Descriptor.pxn == 0
    }

    public var description: String {
        let a = switch access {
        case .el1ReadWrite: "el1-rw"
        case .el1ReadOnly: "el1-ro"
        case .el0ReadWrite: "el0-rw"
        case .el0ReadOnly: "el0-ro"
        }
        var parts = [a]
        if device { parts.append("device") }
        if el1Execute { parts.append("el1-x") }
        if el0Execute { parts.append("el0-x") }
        return parts.joined(separator: ",")
    }
}

public enum PageTableError: Error, Equatable, Sendable, CustomStringConvertible {
    case unaligned(va: UInt64, pa: UInt64, size: UInt64)
    case emptyRange(va: UInt64)
    case virtualAddressOutOfRange(va: UInt64, size: UInt64)
    case physicalAddressOutOfRange(pa: UInt64, size: UInt64)
    case alreadyMapped(va: UInt64)
    case arenaExhausted(capacity: Int)
    case notMapped(va: UInt64)

    public var description: String {
        switch self {
        case let .unaligned(va, pa, size):
            "mapping va \(hex(va)) pa \(hex(pa)) size \(hex(size)) is not 16 KiB-aligned"
        case let .emptyRange(va): "mapping at va \(hex(va)) has size 0"
        case let .virtualAddressOutOfRange(va, size): "va range \(hex(va))+\(hex(size)) is outside the 47-bit address space"
        case let .physicalAddressOutOfRange(pa, size): "pa range \(hex(pa))+\(hex(size)) is outside the 40-bit address space"
        case let .alreadyMapped(va): "va \(hex(va)) is already mapped"
        case let .arenaExhausted(capacity): "the page table arena is full (\(capacity) tables)"
        case let .notMapped(va): "va \(hex(va)) is not mapped"
        }
    }
}

public struct PageTableBuilder: Sendable {
    public let tableArenaGPA: UInt64
    public let tableArenaSize: Int

    private var tablePages: [[UInt64]]
    private var dirtySlots: Set<Int> = [0]

    public init(tableArenaGPA: UInt64, tableArenaSize: Int) {
        precondition(VMLayout.isPageAligned(tableArenaGPA), "table arena GPA must be 16 KiB-aligned")
        precondition(tableArenaSize >= Int(VMLayout.pageSize), "table arena must hold at least one table")
        self.tableArenaGPA = tableArenaGPA
        self.tableArenaSize = tableArenaSize
        tablePages = [Self.emptyTable]
    }

    public init() {
        self.init(tableArenaGPA: VMLayout.pageTableArenaGPA, tableArenaSize: Int(VMLayout.pageTableArenaSize))
    }

    public static func stage3() -> PageTableBuilder {
        PageTableBuilder(tableArenaGPA: VMLayout.stage3PageTableArenaGPA,
                         tableArenaSize: Int(VMLayout.stage3PageTableArenaSize))
    }

    private static let emptyTable = [UInt64](repeating: 0, count: VMLayout.entriesPerTable)

    public var rootGPA: UInt64 { tableArenaGPA }

    public var capacity: Int { tableArenaSize / Int(VMLayout.pageSize) }

    public var tableCount: Int { tablePages.count }

    public static func index(of va: UInt64, level: Int) -> Int {
        precondition((1...3).contains(level), "the walk has levels 1 to 3")
        let shift = VMLayout.pageShift + UInt64(3 - level) * 11
        return Int((va >> shift) & 0x7FF)
    }

    public static func tableDescriptor(nextTableGPA: UInt64) -> UInt64 {
        (nextTableGPA & AArch64.Descriptor.outputAddressMask) | AArch64.Descriptor.validTableOrPage
    }

    public static func pageDescriptor(pa: UInt64, attributes: PageAttributes) -> UInt64 {
        (pa & AArch64.Descriptor.outputAddressMask) | attributes.leafDescriptorBits | AArch64.Descriptor.validTableOrPage
    }

    public mutating func map(va: UInt64, pa: UInt64, size: UInt64, attributes: PageAttributes) throws {
        let page = VMLayout.pageSize
        guard VMLayout.isPageAligned(va), VMLayout.isPageAligned(pa), VMLayout.isPageAligned(size) else {
            throw PageTableError.unaligned(va: va, pa: pa, size: size)
        }
        guard size > 0 else { throw PageTableError.emptyRange(va: va) }
        let vaLimit: UInt64 = 1 << VMLayout.virtualAddressBits
        guard va < vaLimit, size <= vaLimit - va else {
            throw PageTableError.virtualAddressOutOfRange(va: va, size: size)
        }
        let paLimit: UInt64 = 1 << VMLayout.physicalAddressBits
        guard pa < paLimit, size <= paLimit - pa else {
            throw PageTableError.physicalAddressOutOfRange(pa: pa, size: size)
        }

        var work = self
        var offset: UInt64 = 0
        while offset < size {
            try work.mapPage(va: va + offset, pa: pa + offset, attributes: attributes)
            offset += page
        }
        self = work
    }

    public mutating func mapIdentity(_ region: VMLayout.Region) throws {
        try map(va: region.va, pa: region.va, size: region.size, attributes: region.attributes)
    }

    private mutating func mapPage(va: UInt64, pa: UInt64, attributes: PageAttributes) throws {
        let l2 = try nextTable(in: 0, index: Self.index(of: va, level: 1))
        let l3 = try nextTable(in: l2, index: Self.index(of: va, level: 2))
        let i3 = Self.index(of: va, level: 3)
        guard tablePages[l3][i3] & AArch64.Descriptor.typeMask == 0 else {
            throw PageTableError.alreadyMapped(va: va)
        }
        tablePages[l3][i3] = Self.pageDescriptor(pa: pa, attributes: attributes)
        dirtySlots.insert(l3)
    }

    private mutating func nextTable(in table: Int, index: Int) throws -> Int {
        let d = tablePages[table][index]
        if d & AArch64.Descriptor.typeMask == AArch64.Descriptor.validTableOrPage {
            return slot(ofTableAt: d & AArch64.Descriptor.outputAddressMask)!
        }
        guard tablePages.count < capacity else { throw PageTableError.arenaExhausted(capacity: capacity) }
        let newSlot = tablePages.count
        tablePages.append(Self.emptyTable)
        tablePages[table][index] = Self.tableDescriptor(nextTableGPA: gpa(ofSlot: newSlot))
        dirtySlots.insert(table)
        dirtySlots.insert(newSlot)
        return newSlot
    }

    private static func validate(va: UInt64, size: UInt64) throws {
        guard VMLayout.isPageAligned(va), VMLayout.isPageAligned(size) else {
            throw PageTableError.unaligned(va: va, pa: 0, size: size)
        }
        guard size > 0 else { throw PageTableError.emptyRange(va: va) }
        let vaLimit: UInt64 = 1 << VMLayout.virtualAddressBits
        guard va < vaLimit, size <= vaLimit - va else {
            throw PageTableError.virtualAddressOutOfRange(va: va, size: size)
        }
    }

    private func leafLocation(of va: UInt64) -> (slot: Int, index: Int)? {
        var table = 0
        for level in 1...2 {
            let d = tablePages[table][Self.index(of: va, level: level)]
            guard d & AArch64.Descriptor.typeMask == AArch64.Descriptor.validTableOrPage,
                  let next = slot(ofTableAt: d & AArch64.Descriptor.outputAddressMask) else { return nil }
            table = next
        }
        return (table, Self.index(of: va, level: 3))
    }

    @discardableResult
    public mutating func unmap(va: UInt64, size: UInt64) throws -> Int {
        try Self.validate(va: va, size: size)
        let page = VMLayout.pageSize
        let l3Span = page * UInt64(VMLayout.entriesPerTable)
        var cleared = 0
        var cursor = va
        let end = va + size
        while cursor < end {
            guard let (slot, index) = leafLocation(of: cursor) else {
                let next = (cursor & ~(l3Span - 1)) + l3Span
                cursor = next
                continue
            }
            if tablePages[slot][index] & AArch64.Descriptor.typeMask != 0 {
                tablePages[slot][index] = 0
                dirtySlots.insert(slot)
                cleared += 1
            }
            cursor += page
        }
        return cleared
    }

    public mutating func protect(va: UInt64, size: UInt64, attributes: PageAttributes) throws {
        try Self.validate(va: va, size: size)
        let page = VMLayout.pageSize
        var locations: [(slot: Int, index: Int)] = []
        locations.reserveCapacity(Int(size / page))
        var cursor = va
        while cursor < va + size {
            guard let loc = leafLocation(of: cursor),
                  tablePages[loc.slot][loc.index] & AArch64.Descriptor.typeMask == AArch64.Descriptor.validTableOrPage
            else { throw PageTableError.notMapped(va: cursor) }
            locations.append(loc)
            cursor += page
        }
        for (slot, index) in locations {
            let old = tablePages[slot][index]
            let new = Self.pageDescriptor(pa: old & AArch64.Descriptor.outputAddressMask, attributes: attributes)
            if new != old {
                tablePages[slot][index] = new
                dirtySlots.insert(slot)
            }
        }
    }

    public var hasDirtyTables: Bool { !dirtySlots.isEmpty }

    public mutating func drainDirtyTables() -> [(gpa: UInt64, bytes: [UInt8])] {
        let slots = dirtySlots.sorted()
        dirtySlots.removeAll()
        return slots.map { (gpa(ofSlot: $0), bytes(ofSlot: $0)) }
    }

    private func gpa(ofSlot slot: Int) -> UInt64 { tableArenaGPA + UInt64(slot) * VMLayout.pageSize }

    private func slot(ofTableAt gpa: UInt64) -> Int? {
        guard gpa >= tableArenaGPA else { return nil }
        let slot = Int((gpa - tableArenaGPA) / VMLayout.pageSize)
        return slot < tablePages.count ? slot : nil
    }

    public var tables: [(gpa: UInt64, bytes: [UInt8])] {
        tablePages.indices.map { (gpa(ofSlot: $0), bytes(ofSlot: $0)) }
    }

    private func bytes(ofSlot slot: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Int(VMLayout.pageSize))
        for e in tablePages[slot] { appendLE(e, to: &bytes) }
        return bytes
    }

    public func descriptor(tableGPA: UInt64, index: Int) -> UInt64? {
        guard let slot = slot(ofTableAt: tableGPA), (0..<VMLayout.entriesPerTable).contains(index) else { return nil }
        return tablePages[slot][index]
    }

    public func translate(_ va: UInt64) -> (pa: UInt64, attributes: PageAttributes)? {
        guard va < 1 << VMLayout.virtualAddressBits else { return nil }
        var table = 0
        for level in 1...2 {
            let d = tablePages[table][Self.index(of: va, level: level)]
            guard d & AArch64.Descriptor.typeMask == AArch64.Descriptor.validTableOrPage,
                  let next = slot(ofTableAt: d & AArch64.Descriptor.outputAddressMask) else { return nil }
            table = next
        }
        let d = tablePages[table][Self.index(of: va, level: 3)]
        guard d & AArch64.Descriptor.typeMask == AArch64.Descriptor.validTableOrPage else { return nil }
        let pa = (d & AArch64.Descriptor.outputAddressMask) | (va & (VMLayout.pageSize - 1))
        return (pa, PageAttributes(leafDescriptor: d))
    }
}
