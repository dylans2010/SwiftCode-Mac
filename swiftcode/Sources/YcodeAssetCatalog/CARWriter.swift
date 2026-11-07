import Foundation

public struct CARWriter: Sendable {
    public struct WriteError: Error, CustomStringConvertible {
        public var message: String
        public var description: String { "Assets.car: \(message)" }
    }

    public var platform: CARPlatform
    public var deploymentTarget: String
    public var compression: CARCompression
    public var renditions: [CARRendition] = []
    public var mainVersion = "@(#)PROGRAM:SwiftCode  PROJECT:SwiftCodeAssetCatalog-1"
    public var versionString = "SwiftCode asset catalog compiler"
    public var authoringTool = "SwiftCode asset catalog compiler"

    public init(platform: CARPlatform, deploymentTarget: String = "", compression: CARCompression = .lzfse) {
        self.platform = platform
        self.deploymentTarget = deploymentTarget
        self.compression = compression
    }

    public mutating func add(_ r: CARRendition) { renditions.append(r) }

    static func keyBytes(_ k: [UInt16]) -> [UInt8] { k.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }

    public static func identifiers(for names: [String]) -> [String: UInt16] {
        var used = Set<UInt16>()
        var out: [String: UInt16] = [:]
        for n in Set(names).sorted(by: { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }) {
            var h: UInt32 = 2_166_136_261
            for b in n.utf8 { h = (h ^ UInt32(b)) &* 16_777_619 }
            var id = UInt16(truncatingIfNeeded: h ^ (h >> 16))
            while id == 0 || used.contains(id) { id &+= 1 }
            used.insert(id)
            out[n] = id
        }
        return out
    }

    static func facetPart(_ rs: [CARRendition]) -> UInt16 {
        rs.contains { $0.content.part == CARPart.iconImage } ? CARPart.iconImage : rs.first?.content.part ?? CARPart.image
    }

    public func data() throws -> Data {
        let names = renditions.map(\.name)
        let ids = Self.identifiers(for: names)
        let format = platform.keyFormat

        var entries: [(key: [UInt16], value: [UInt8])] = []
        var seen = Set<[UInt16]>()
        for r in renditions {
            var a = r.attributes
            a[.element] = carCatalogElement
            a[.part] = r.content.part
            a[.identifier] = ids[r.name]!
            if a[.scale] == nil || a[.scale] == 0 { a[.scale] = 1 }
            let key = format.map { a[$0] ?? 0 }
            guard seen.insert(key).inserted else {
                throw WriteError(message: "two renditions of \"\(r.name)\" have the same key \(key)")
            }
            entries.append((key, CSI.record(r, platform: platform, compression: compression)))
        }
        entries.sort { Self.keyBytes($0.key).lexicographicallyPrecedes(Self.keyBytes($1.key)) }

        var bom = BOMWriter()
        bom.addVariable("CARHEADER", bytes: header(renditionCount: entries.count))
        bom.addVariable("EXTENDED_METADATA", bytes: metadata())
        var kf = ByteWriter()
        kf.tag("tmfk")
        kf.u32le(0)
        kf.u32le(UInt32(format.count))
        for f in format { kf.u32le(f.rawValue) }
        bom.addVariable("KEYFORMAT", bytes: kf.bytes)

        var appearances: [String: UInt16] = [platform.appearanceName(.any): 0]
        for r in renditions {
            if let n = r.attributes[.appearance], n != 0,
               let a = CARAppearance.allCases.first(where: { platform.appearanceNumber($0) == n }) {
                appearances[platform.appearanceName(a)] = n
            }
        }
        let akeys = appearances.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        bom.addTree("APPEARANCEKEYS", entries: akeys.map { k in
            var w = ByteWriter()
            w.u16le(appearances[k]!)
            return (Array(k.utf8), w.bytes)
        }, keys: .variable)

        var byName: [String: [CARRendition]] = [:]
        for r in renditions { byName[r.name, default: []].append(r) }
        let fkeys = byName.keys.sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        bom.addTree("FACETKEYS", entries: fkeys.map { n in
            var w = ByteWriter()
            w.u16le(0)
            w.u16le(0)
            w.u16le(3)
            for (attr, v) in [(CARAttribute.element, carCatalogElement), (.part, Self.facetPart(byName[n]!)), (.identifier, ids[n]!)] {
                w.u16le(UInt16(attr.rawValue))
                w.u16le(v)
            }
            return (Array(n.utf8), w.bytes)
        }, keys: .variable)

        bom.addTree("RENDITIONS", entries: entries.map { (Self.keyBytes($0.key), $0.value) }, keys: .fixed(format.count * 2))
        return bom.data()
    }

    func header(renditionCount: Int) -> [UInt8] {
        var w = ByteWriter()
        w.tag("RATC")
        w.u32le(1010)
        w.u32le(17)
        w.u32le(0)
        w.u32le(UInt32(renditionCount))
        w.padded(mainVersion, 128)
        w.padded(versionString, 256)
        w.zeros(16)
        w.u32le(0)
        w.u32le(2)
        w.u32le(1)
        w.u32le(platform.keySemantics)
        return w.bytes
    }

    func metadata() -> [UInt8] {
        var w = ByteWriter()
        w.tag("META")
        w.padded("", 256)
        w.padded(deploymentTarget, 256)
        w.padded(platform.metadataPlatform, 256)
        w.padded(authoringTool, 256)
        return w.bytes
    }
}

enum CSI {
    static func record(_ r: CARRendition, platform: CARPlatform, compression: CARCompression) -> [UInt8] {
        var tlv = ByteWriter()
        func entry(_ type: UInt32, _ body: (inout ByteWriter) -> Void) {
            var b = ByteWriter()
            body(&b)
            tlv.u32le(type)
            tlv.u32le(UInt32(b.count))
            tlv.append(b.bytes)
        }
        var width: UInt32 = 0, height: UInt32 = 0, scale: UInt32 = 0
        var pixelFormat: [UInt8] = [0, 0, 0, 0]
        var colorSpace: UInt32 = 0
        var payload = ByteWriter()

        switch r.content {
        case .image(let bmp), .iconImage(let bmp):
            width = UInt32(bmp.width)
            height = UInt32(bmp.height)
            scale = UInt32(r.attributes[.scale] ?? 1) * 100
            pixelFormat = Array("BGRA".utf8)
            colorSpace = 1
            entry(1001) { $0.u32le(1); $0.u32le(0); $0.u32le(0); $0.u32le(width); $0.u32le(height) }
            entry(1003) { $0.u32le(1); $0.zeros(16); $0.u32le(width); $0.u32le(height) }
            entry(1004) { $0.u32le(0); $0.f32le(1) }
            entry(1006) { $0.u32le(1) }
            entry(1007) { $0.u32le(width * 4) }
            let version: UInt32 = { if case .iconImage = r.content { return platform.celmVersion }; return 1 }()
            payload.append(celm(bmp, version: version, compression: compression))
        case .color(let c):
            entry(1004) { $0.u32le(0); $0.f32le(0) }
            entry(1006) { $0.u32le(1) }
            payload.tag("RLOC")
            payload.u32le(1)
            payload.u32le(UInt32(c.colorSpace))
            payload.u32le(UInt32(c.components.count))
            for x in c.components { payload.f64le(x) }
        case .multisize(let sizes):
            entry(1004) { $0.u32le(0); $0.f32le(0) }
            entry(1006) { $0.u32le(1) }
            payload.tag("SISM")
            payload.u32le(1)
            payload.u32le(UInt32(sizes.count))
            for s in sizes {
                payload.u32le(s.width)
                payload.u32le(s.height)
                payload.u32le(UInt32(s.index))
            }
        }

        var w = ByteWriter(capacity: 184 + tlv.count + payload.count)
        w.tag("ISTC")
        w.u32le(1)
        w.u32le(r.flags)
        w.u32le(width)
        w.u32le(height)
        w.u32le(scale)
        w.append(pixelFormat)
        w.u32le(colorSpace)
        w.u32le(0)
        w.u16le(r.content.layout)
        w.u16le(0)
        w.padded(r.renditionName, 128)
        w.u32le(UInt32(tlv.count))
        w.u32le(1)
        w.u32le(0)
        w.u32le(UInt32(payload.count))
        w.append(tlv.bytes)
        w.append(payload.bytes)
        return w.bytes
    }

    static func celm(_ bmp: Bitmap, version: UInt32, compression: CARCompression) -> [UInt8] {
        let pixels = bmp.premultipliedBGRA
        var w = ByteWriter()
        w.tag("MLEC")
        w.u32le(version)
        switch compression {
        case .none:
            w.u32le(0)
            w.u32le(UInt32(pixels.count))
            w.append(pixels)
        case .lzfse:
            let rowBytes = bmp.width * 4
            let rowsPerChunk = max(1, bmp.height / 3)
            var chunks: [(rows: Int, data: [UInt8])] = []
            var y = 0
            while y < bmp.height {
                let rows = bmp.height - y < 2 * rowsPerChunk ? bmp.height - y : rowsPerChunk
                chunks.append((rows, LZFSE.encode(Array(pixels[y * rowBytes..<(y + rows) * rowBytes]))))
                y += rows
            }
            w.u32le(4)
            w.u32le(UInt32(chunks.count))
            for c in chunks {
                w.tag("KCBC")
                w.u32le(0)
                w.u32le(0)
                w.u32le(UInt32(c.rows))
                w.u32le(UInt32(c.data.count))
                w.append(c.data)
            }
        }
        return w.bytes
    }
}
