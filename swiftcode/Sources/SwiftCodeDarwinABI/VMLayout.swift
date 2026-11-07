public enum VMLayout {

    public static let pageShift: UInt64 = 14
    public static let pageSize: UInt64 = 1 << pageShift
    public static let entriesPerTable = Int(pageSize / 8)
    public static let virtualAddressBits: UInt64 = 47
    public static let t0sz: UInt64 = 64 - virtualAddressBits
    public static let physicalAddressBits: UInt64 = 40

    public static let doorbellGPA: UInt64 = 0x0900_0000
    public static let doorbellSize: UInt64 = 0x4000

    public static let ramGPA: UInt64 = 0x4000_0000
    public static let ramSize: UInt64 = 512 << 20
    public static let ramSlot: UInt32 = 0

    public static let shimGPA: UInt64 = ramGPA + 0x0000_0000
    public static let shimRegionSize: UInt64 = 1 << 20
    public static let shimEntryGPA: UInt64 = shimGPA

    public static let bootInfoGPA: UInt64 = ramGPA + 0x0010_0000
    public static let bootInfoRegionSize: UInt64 = pageSize

    public static let trapFrameGPA: UInt64 = ramGPA + 0x0010_4000
    public static let trapFrameRegionSize: UInt64 = pageSize

    public static let el1StackGPA: UInt64 = ramGPA + 0x0011_0000
    public static let el1StackSize: UInt64 = 64 << 10
    public static let el1StackTop: UInt64 = el1StackGPA + el1StackSize

    public static let pageTableArenaGPA: UInt64 = ramGPA + 0x0020_0000
    public static let pageTableArenaSize: UInt64 = 8 << 20

    public static let el0PoolGPA: UInt64 = ramGPA + 0x0100_0000
    public static let el0PoolSize: UInt64 = ramSize - 0x0100_0000

    public struct Region: Equatable, Hashable, Sendable {
        public var name: String
        public var va: UInt64
        public var size: UInt64
        public var attributes: PageAttributes

        public init(name: String, va: UInt64, size: UInt64, attributes: PageAttributes) {
            self.name = name
            self.va = va
            self.size = size
            self.attributes = attributes
        }

        public var end: UInt64 { va + size }
    }

    public static let el1Regions: [Region] = [
        Region(name: "shim", va: shimGPA, size: shimRegionSize,
               attributes: PageAttributes(access: .el1ReadWrite, el1Execute: true)),
        Region(name: "el1-data", va: bootInfoGPA, size: el1StackTop - bootInfoGPA,
               attributes: PageAttributes(access: .el1ReadWrite)),
        Region(name: "page-tables", va: pageTableArenaGPA, size: pageTableArenaSize,
               attributes: PageAttributes(access: .el1ReadWrite)),
        Region(name: "doorbell", va: doorbellGPA, size: doorbellSize,
               attributes: PageAttributes(access: .el1ReadWrite, device: true)),
    ]

    public static let selfTestImageVA: UInt64 = 0x1_0000_0000
    public static let selfTestTextSize: UInt64 = pageSize
    public static let selfTestDataVA: UInt64 = 0x1_0000_4000
    public static let selfTestDataMagic: UInt64 = 0x5943_4F44_4531_3645

    public static let el0StackTop: UInt64 = 0x1_7000_0000
    public static let el0StackSize: UInt64 = 64 << 10
    public static let el0StackBase: UInt64 = el0StackTop - el0StackSize

    public static let commpageVA: UInt64 = 0xF_FFFF_C000
    public static let commpageSize: UInt64 = pageSize

    public static func selfTestRegions(imageSize: UInt64) -> [Region] {
        var regions = [
            Region(name: "text", va: selfTestImageVA, size: selfTestTextSize,
                   attributes: PageAttributes(access: .el0ReadOnly, el0Execute: true)),
        ]
        let remainder = imageSize > selfTestTextSize ? imageSize - selfTestTextSize : 0
        if remainder > 0 {
            regions.append(Region(name: "data", va: selfTestDataVA, size: roundUpToPage(remainder),
                                  attributes: PageAttributes(access: .el0ReadWrite)))
        }
        regions.append(Region(name: "stack", va: el0StackBase, size: el0StackSize,
                              attributes: PageAttributes(access: .el0ReadWrite)))
        regions.append(Region(name: "commpage", va: commpageVA, size: commpageSize,
                              attributes: PageAttributes(access: .el0ReadOnly)))
        return regions
    }

    public static let el1BootPSTATE: UInt64 = AArch64.SPSR.daifMask | AArch64.SPSR.modeEL1h
    public static let el0InitialSPSR: UInt64 = AArch64.SPSR.daifMask | AArch64.SPSR.modeEL0t

    public static let guestPID: Int32 = 100
    public static let fatalExitStatus: Int32 = 70

    public static let addressWithoutTag: UInt64 = 0x00FF_FFFF_FFFF_FFFF
    public static let tcrEL1: UInt64 = AArch64.TCR.recommended
    public static let mairEL1: UInt64 = AArch64.MAIR.recommended
    public static let sctlrEL1: UInt64 = AArch64.SCTLR.recommended

    static func roundUpToPage(_ v: UInt64) -> UInt64 { (v + pageSize - 1) & ~(pageSize - 1) }
    static func isPageAligned(_ v: UInt64) -> Bool { v & (pageSize - 1) == 0 }
}

extension VMLayout {

    public static let stage3RAMSize: UInt64 = 1 << 30
    public static let stage3PageTableArenaGPA: UInt64 = pageTableArenaGPA
    public static let stage3PageTableArenaSize: UInt64 = 64 << 20

    public static let anonymousPoolGPA: UInt64 = 0x10_0000_0000
    public static let anonymousPoolSize: UInt64 = 16 << 30
    public static let fileSlotGPABase: UInt64 = 0x20_0000_0000
    public static let firstExtraMemslot: UInt32 = 1

    public static let stage3EL1Regions: [Region] = el1Regions.map { r in
        guard r.name == "page-tables" else { return r }
        return Region(name: r.name, va: stage3PageTableArenaGPA, size: stage3PageTableArenaSize, attributes: r.attributes)
    }

    public static let userVAFloor: UInt64 = 0x1_0000_0000
    public static let userVALimit: UInt64 = 0xF_C000_0000
    public static let mainExecutableBaseVA: UInt64 = 0x1_0000_0000

    public static let userStackTop: UInt64 = 0x1_6FE0_0000
    public static let userStackSize: UInt64 = 8 << 20
    public static let userStackBase: UInt64 = userStackTop - userStackSize

    public static let sharedRegionBase: UInt64 = 0x1_8000_0000
    public static let sharedRegionSize: UInt64 = 0x1_8000_0000
    public static let sharedRegionEnd: UInt64 = sharedRegionBase + sharedRegionSize

    public static let dyldSimBaseVA: UInt64 = 0x3_0000_0000

    public static let anonymousVABase: UInt64 = 0x3_2000_0000

    public static let commpageReservationBase: UInt64 = 0xF_C000_0000
    public static let commpageReservationEnd: UInt64 = 0x10_0000_0000
    public static let readOnlyCommpageVA: UInt64 = 0xF_FFFF_4000

    public static let hostPageVA: UInt64 = 0x3_1000_0000
    public static let hostPageSize: UInt64 = 0x1_0000

    public static let hostPageCodeOffset: UInt64 = 0x0000
    public static let hostPageCodeSize: UInt64 = 0x4000
    public static let hostPageRODataOffset: UInt64 = 0x4000
    public static let hostPageRODataSize: UInt64 = 0x4000
    public static let hostPageRWDataOffset: UInt64 = 0x8000
    public static let hostPageRWDataSize: UInt64 = 0x8000

    public static let hostPageHelpersOffset: UInt64 = 0x4000
    public static let hostPageHelpersSize: UInt64 = 544
    public static let helpersTableVersion: UInt64 = 18
    public static let helpersSlotCount = 67
    public static let hostPageErrnoOffset: UInt64 = 0x8000
    public static let hostPageStartGlueOffset: UInt64 = 0x8008
    public static let hostPageLaunchBlockOffset: UInt64 = 0x8040
    public static let hostPageLaunchBlockSize: UInt64 = 96
    public static let hostPageAllImageInfosOffset: UInt64 = 0x8100
    public static let hostPageAllImageInfosSize: UInt64 = 368
    public static let hostPageImageInfoStorageOffset: UInt64 = 0x8300
    public static let hostPageImageInfoStorageSize: UInt64 = 0x800
    public static let hostPageScratchOffset: UInt64 = 0x9000
    public static let hostPageScratchSize: UInt64 = 0x1000

    public static let hostPageEntryVA: UInt64 = hostPageVA + hostPageCodeOffset

    public static let hostPageRegions: [Region] = [
        Region(name: "host-code", va: hostPageVA + hostPageCodeOffset, size: hostPageCodeSize,
               attributes: PageAttributes(access: .el0ReadOnly, el0Execute: true)),
        Region(name: "host-rodata", va: hostPageVA + hostPageRODataOffset, size: hostPageRODataSize,
               attributes: PageAttributes(access: .el0ReadOnly)),
        Region(name: "host-rwdata", va: hostPageVA + hostPageRWDataOffset, size: hostPageRWDataSize,
               attributes: PageAttributes(access: .el0ReadWrite)),
    ]
}

public enum AArch64 {
    public enum TCR {
        public static func t0sz(_ v: UInt64) -> UInt64 { (v & 0x3F) << 0 }
        public static let epd0: UInt64 = 1 << 7
        public static func irgn0(_ v: UInt64) -> UInt64 { (v & 3) << 8 }
        public static func orgn0(_ v: UInt64) -> UInt64 { (v & 3) << 10 }
        public static func sh0(_ v: UInt64) -> UInt64 { (v & 3) << 12 }
        public static func tg0(_ v: UInt64) -> UInt64 { (v & 3) << 14 }
        public static func t1sz(_ v: UInt64) -> UInt64 { (v & 0x3F) << 16 }
        public static let a1: UInt64 = 1 << 22
        public static let epd1: UInt64 = 1 << 23
        public static func tg1(_ v: UInt64) -> UInt64 { (v & 3) << 30 }
        public static func ips(_ v: UInt64) -> UInt64 { (v & 7) << 32 }
        public static let tbi0: UInt64 = 1 << 37

        public static let cacheWriteBackAllocate: UInt64 = 0b01
        public static let shareabilityInner: UInt64 = 0b11
        public static let tg0Granule16K: UInt64 = 0b10
        public static let tg1Granule16K: UInt64 = 0b01
        public static let ips40Bit: UInt64 = 0b010

        public static let recommended: UInt64 =
            t0sz(VMLayout.t0sz)
            | irgn0(cacheWriteBackAllocate) | orgn0(cacheWriteBackAllocate)
            | sh0(shareabilityInner)
            | tg0(tg0Granule16K)
            | t1sz(VMLayout.t0sz)
            | epd1
            | tg1(tg1Granule16K)
            | ips(ips40Bit)
            | tbi0
    }

    public enum MAIR {
        public static let normalWriteBack: UInt8 = 0xFF
        public static let deviceNGnRnE: UInt8 = 0x00
        public static let normalIndex: UInt64 = 0
        public static let deviceIndex: UInt64 = 1

        public static func attr(_ index: UInt64, _ value: UInt8) -> UInt64 { UInt64(value) << (8 * index) }

        public static let recommended: UInt64 = attr(normalIndex, normalWriteBack) | attr(deviceIndex, deviceNGnRnE)
    }

    public enum SCTLR {
        public static let m: UInt64 = 1 << 0
        public static let a: UInt64 = 1 << 1
        public static let c: UInt64 = 1 << 2
        public static let sa: UInt64 = 1 << 3
        public static let sa0: UInt64 = 1 << 4
        public static let itd: UInt64 = 1 << 7
        public static let sed: UInt64 = 1 << 8
        public static let eos: UInt64 = 1 << 11
        public static let i: UInt64 = 1 << 12
        public static let dze: UInt64 = 1 << 14
        public static let uct: UInt64 = 1 << 15
        public static let nTWI: UInt64 = 1 << 16
        public static let nTWE: UInt64 = 1 << 18
        public static let wxn: UInt64 = 1 << 19
        public static let tscxt: UInt64 = 1 << 20
        public static let eis: UInt64 = 1 << 22
        public static let span: UInt64 = 1 << 23
        public static let e0e: UInt64 = 1 << 24
        public static let ee: UInt64 = 1 << 25
        public static let uci: UInt64 = 1 << 26
        public static let nTLSMD: UInt64 = 1 << 28
        public static let lsmaoe: UInt64 = 1 << 29

        public static let res1: UInt64 = itd | sed | eos | tscxt | eis | span | nTLSMD | lsmaoe

        public static let recommended: UInt64 =
            m | c | sa | sa0 | i | dze | uct | nTWI | nTWE | uci | span | eis | eos | res1
    }

    public enum SPSR {
        public static let n: UInt64 = 1 << 31
        public static let z: UInt64 = 1 << 30
        public static let c: UInt64 = 1 << 29
        public static let v: UInt64 = 1 << 28
        public static let d: UInt64 = 1 << 9
        public static let a: UInt64 = 1 << 8
        public static let i: UInt64 = 1 << 7
        public static let f: UInt64 = 1 << 6
        public static let daifMask: UInt64 = d | a | i | f
        public static let modeEL0t: UInt64 = 0b0000
        public static let modeEL1t: UInt64 = 0b0100
        public static let modeEL1h: UInt64 = 0b0101
    }

    public enum Descriptor {
        public static let validTableOrPage: UInt64 = 0b11
        public static let typeMask: UInt64 = 0b11
        public static func attrIndx(_ v: UInt64) -> UInt64 { (v & 7) << 2 }
        public static let ns: UInt64 = 1 << 5
        public static func ap(_ v: UInt64) -> UInt64 { (v & 3) << 6 }
        public static func sh(_ v: UInt64) -> UInt64 { (v & 3) << 8 }
        public static let af: UInt64 = 1 << 10
        public static let nG: UInt64 = 1 << 11
        public static let pxn: UInt64 = 1 << 53
        public static let uxn: UInt64 = 1 << 54
        public static let outputAddressMask: UInt64 = 0x0000_FFFF_FFFF_C000
    }
}
