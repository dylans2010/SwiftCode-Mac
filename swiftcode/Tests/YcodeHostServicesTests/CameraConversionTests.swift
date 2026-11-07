import CYcodeCamera
import CYcodeCodec
import Foundation
import Testing
@testable import YcodeHostServices

@Suite struct CameraConversionTests {
    func bgr(_ y: Int, _ cb: Int, _ cr: Int, full: Bool = false, matrix: Int = 601) -> [UInt8] {
        var out: [UInt8] = [0, 0, 0]
        ycam_ycbcr_to_bgr(Int32(y), Int32(cb), Int32(cr), full ? 1 : 0, Int32(matrix), &out)
        return out
    }

    @Test func matrices() {
        #expect(bgr(16, 128, 128) == [0, 0, 0])
        #expect(bgr(235, 128, 128) == [255, 255, 255])
        #expect(bgr(126, 128, 128) == [128, 128, 128])
        #expect(bgr(126, 128, 128, matrix: 709) == [128, 128, 128])
        #expect(bgr(81, 90, 240) == [0, 0, 254])
        #expect(bgr(63, 102, 240, matrix: 709) == [0, 1, 255])
        #expect(bgr(128, 128, 128, full: true) == [128, 128, 128])
        #expect(bgr(0, 128, 255, full: true) == [0, 0, 178])
        #expect(bgr(255, 128, 128, full: true) == [255, 255, 255])
        #expect(bgr(29, 255, 107, full: true) == [254, 0, 0])
    }

    @Test func rangeMaps() {
        #expect(ycam_map_luma(16, 0, 1) == 0 && ycam_map_luma(235, 0, 1) == 255 && ycam_map_luma(126, 0, 1) == 128)
        #expect(ycam_map_luma(5, 0, 1) == 0 && ycam_map_luma(250, 0, 1) == 255)
        #expect(ycam_map_luma(0, 1, 0) == 16 && ycam_map_luma(255, 1, 0) == 235 && ycam_map_luma(128, 1, 0) == 126)
        #expect(ycam_map_chroma(16, 0, 1) == 0 && ycam_map_chroma(240, 0, 1) == 255 && ycam_map_chroma(128, 0, 1) == 128)
        #expect(ycam_map_chroma(0, 1, 0) == 16 && ycam_map_chroma(255, 1, 0) == 240 && ycam_map_chroma(128, 1, 0) == 128)
        #expect(ycam_map_chroma(100, 0, 0) == 100 && ycam_map_luma(77, 1, 1) == 77)
    }

    let yuyv: [UInt8] = [10, 100, 20, 150, 30, 110, 40, 160,
                         50, 102, 60, 151, 70, 113, 80, 170]

    func convert(_ bytes: [UInt8], _ format: CameraSourceFormat, width: Int, height: Int, bytesPerLine: Int,
                 to output: CameraPixelFormat, colorimetry: CameraColorimetry = .video601) throws -> (CameraSurfaceLayout, [UInt8]) {
        let layout = CameraSurfaceLayout.make(output, width: width, height: height)
        var memory = [UInt8](repeating: 0xEE, count: layout.allocationSize)
        try bytes.withUnsafeBytes { raw in
            let frame = CameraRawFrame(format: format, width: width, height: height, bytesPerLine: bytesPerLine, bytes: raw,
                                       colorimetry: colorimetry, deviceSequence: 0, timestamp: 0, synthetic: false, token: 0)
            try memory.withUnsafeMutableBytes { try CameraConverter().convert(frame, into: $0.baseAddress!, layout: layout) }
        }
        return (layout, memory)
    }

    @Test func yuyvToBiPlanar() throws {
        let (l, m) = try convert(yuyv, .yuyv, width: 4, height: 2, bytesPerLine: 8, to: .biPlanar420Video)
        let y = l.planes[0], c = l.planes[1]
        #expect(Array(m[y.offset..<(y.offset + 4)]) == [10, 20, 30, 40])
        #expect(Array(m[(y.offset + y.bytesPerRow)..<(y.offset + y.bytesPerRow + 4)]) == [50, 60, 70, 80])
        #expect(Array(m[c.offset..<(c.offset + 4)]) == [101, 151, 112, 165])
        let (lf, mf) = try convert(yuyv, .yuyv, width: 4, height: 2, bytesPerLine: 8, to: .biPlanar420Full)
        let yf = lf.planes[0], cf = lf.planes[1]
        #expect(Array(mf[yf.offset..<(yf.offset + 4)]) == [0, 5, 16, 28])
        #expect(Array(mf[cf.offset..<(cf.offset + 4)]) == [ycam_map_chroma(101, 0, 1), ycam_map_chroma(151, 0, 1),
                                                           ycam_map_chroma(112, 0, 1), ycam_map_chroma(165, 0, 1)])
    }

    @Test func yuyvAndUYVYToBGRA() throws {
        let (l, m) = try convert(yuyv, .yuyv, width: 4, height: 2, bytesPerLine: 8, to: .bgra)
        #expect(l.bytesPerRow == 128)
        #expect(Array(m[4..<8]) == bgr(20, 100, 150) + [255])
        #expect(Array(m[(128 + 8)..<(128 + 12)]) == bgr(70, 113, 170) + [255])
        var uyvy: [UInt8] = []
        for i in stride(from: 0, to: yuyv.count, by: 4) { uyvy += [yuyv[i + 1], yuyv[i], yuyv[i + 3], yuyv[i + 2]] }
        let (_, mu) = try convert(uyvy, .uyvy, width: 4, height: 2, bytesPerLine: 8, to: .bgra)
        #expect(Array(mu[0..<256]) == Array(m[0..<256]))
    }

    @Test func planarSourcesToBGRA() throws {
        let nv12: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 200, 140, 60]
        let (_, m) = try convert(nv12, .nv12, width: 4, height: 2, bytesPerLine: 4, to: .bgra)
        #expect(Array(m[0..<4]) == bgr(10, 90, 200) + [255])
        #expect(Array(m[(128 + 12)..<(128 + 16)]) == bgr(80, 140, 60) + [255])
        let i420: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80, 90, 140, 200, 60]
        let yv12: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80, 200, 60, 90, 140]
        let (_, mi) = try convert(i420, .yu12, width: 4, height: 2, bytesPerLine: 4, to: .bgra)
        let (_, mv) = try convert(yv12, .yv12, width: 4, height: 2, bytesPerLine: 4, to: .bgra)
        #expect(Array(mi[0..<256]) == Array(m[0..<256]) && Array(mv[0..<256]) == Array(m[0..<256]))
        #expect(throws: CameraConversionError.shortFrame) {
            _ = try convert(Array(nv12.prefix(10)), .nv12, width: 4, height: 2, bytesPerLine: 4, to: .bgra)
        }
    }

    @Test func surfaceLayouts() {
        let v = CameraSurfaceLayout.make(.biPlanar420Video, width: 1280, height: 720)
        #expect(v.planes == [
            IOSurfaceHostService.HostPlane(offset: 0, width: 1280, height: 720, bytesPerRow: 1280, bytesPerElement: 1, size: 921_600),
            IOSurfaceHostService.HostPlane(offset: 933_888, width: 640, height: 360, bytesPerRow: 1280, bytesPerElement: 2, size: 460_800),
        ])
        #expect(v.allocationSize == 1_409_024 && v.bytesPerRow == 0)
        #expect(v.attachments(.video601) == ["YCbCrMatrixIndex": 6, "ColorPrimariesIndex": 1, "TransferFunctionIndex": 1])
        let b = CameraSurfaceLayout.make(.bgra, width: 1280, height: 720)
        #expect(b.bytesPerRow == 5120 && b.allocationSize == 3_686_400 && b.planes.isEmpty && b.bytesPerElement == 4)
        let odd = CameraSurfaceLayout.make(.biPlanar420Full, width: 641, height: 481)
        #expect(odd.planes[0].bytesPerRow == 768 && odd.planes[1].width == 321 && odd.planes[1].height == 241)
        #expect(odd.planes[1].bytesPerRow == 768)
        #expect(CameraPixelFormat.biPlanar420Video.description == "420v" && CameraPixelFormat(name: "BGRA") == .bgra)
        #expect(CameraSourceFormat.mjpeg.rawValue == 0x4750_4A4D && CameraSourceFormat.yuyv.description == "YUYV")
    }

    struct BitWriter {
        var bytes: [UInt8] = []
        var acc: UInt32 = 0, n = 0
        mutating func put(_ value: Int, _ count: Int) {
            for i in stride(from: count - 1, through: 0, by: -1) {
                acc = acc << 1 | UInt32((value >> i) & 1)
                n += 1
                if n == 8 { flushByte() }
            }
        }
        mutating func flushByte() {
            bytes.append(UInt8(acc))
            if acc == 0xFF { bytes.append(0) }
            (acc, n) = (0, 0)
        }
        mutating func pad() { while n != 0 { put(1, 1) } }
    }

    func dcCodes(_ bits: [Int]) -> [(code: Int, length: Int)] {
        var codes: [(Int, Int)] = [], code = 0
        for (i, n) in bits.enumerated() {
            for _ in 0..<n { codes.append((code, i + 1)); code += 1 }
            code <<= 1
        }
        return codes
    }

    func putDC(_ w: inout BitWriter, _ diff: Int, _ table: [(code: Int, length: Int)]) {
        var s = 0
        while (1 << s) <= abs(diff) { s += 1 }
        w.put(table[s].code, table[s].length)
        if s > 0 { w.put(diff > 0 ? diff : diff + (1 << s) - 1, s) }
    }

    func flatJPEG(luma: [[Int]], cb: [Int], cr: [Int]) -> [UInt8] {
        let lumaDC = dcCodes([0, 1, 5, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0])
        let chromaDC = dcCodes([0, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0])
        var j: [UInt8] = [0xFF, 0xD8]
        j += [0xFF, 0xDB, 0, 67, 0] + [UInt8](repeating: 1, count: 64)
        j += [0xFF, 0xDB, 0, 67, 1] + [UInt8](repeating: 1, count: 64)
        j += [0xFF, 0xC0, 0, 17, 8, 0, 16, 0, 32, 3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]
        j += [0xFF, 0xDD, 0, 4, 0, 1]
        j += [0xFF, 0xDA, 0, 12, 3, 1, 0x00, 2, 0x11, 3, 0x11, 0, 63, 0]
        for mcu in 0..<2 {
            var w = BitWriter()
            var pred = 0
            for level in luma[mcu] {
                let dc = (level - 128) * 8
                putDC(&w, dc - pred, lumaDC)
                pred = dc
                w.put(0b1010, 4)
            }
            for level in [cb[mcu], cr[mcu]] {
                putDC(&w, (level - 128) * 8, chromaDC)
                w.put(0b00, 2)
            }
            w.pad()
            j += w.bytes
            if mcu == 0 { j += [0xFF, 0xD0] }
        }
        return j + [0xFF, 0xD9]
    }

    @Test func jpegFlatBlocksWithRestarts() throws {
        let luma = [[16, 235, 128, 64], [200, 30, 99, 180]]
        let jpeg = flatJPEG(luma: luma, cb: [90, 160], cr: [240, 40])
        let d = ycam_jpeg_new()!
        defer { ycam_jpeg_free(d) }
        #expect(ycam_jpeg_decode(d, jpeg, jpeg.count) == 0)
        var img = ycam_jpeg_image()
        ycam_jpeg_image_info(d, &img)
        #expect(img.width == 32 && img.height == 16 && img.components == 3 && img.hmax == 2 && img.vmax == 2)
        #expect(img.h.1 == 1 && img.v.1 == 1)
        func sample(_ plane: UnsafePointer<UInt8>?, _ stride: Int32, _ x: Int, _ y: Int) -> UInt8 { plane![y * Int(stride) + x] }
        for mcu in 0..<2 {
            for (b, level) in luma[mcu].enumerated() {
                let x0 = mcu * 16 + (b % 2) * 8, y0 = (b / 2) * 8
                for (x, y) in [(x0, y0), (x0 + 7, y0 + 7), (x0 + 3, y0 + 5)] {
                    #expect(Int(sample(img.plane.0, img.stride.0, x, y)) == level)
                }
            }
        }
        #expect(sample(img.plane.1, img.stride.1, 0, 0) == 90 && sample(img.plane.1, img.stride.1, 8, 7) == 160)
        #expect(sample(img.plane.2, img.stride.2, 7, 7) == 240 && sample(img.plane.2, img.stride.2, 15, 0) == 40)
        let (l, m) = try convert(jpeg, .mjpeg, width: 32, height: 16, bytesPerLine: 0, to: .biPlanar420Full)
        #expect(m[l.planes[0].offset + 8] == 235 && m[l.planes[1].offset] == 90 && m[l.planes[1].offset + 1] == 240)
        #expect(m[l.planes[1].offset + 16] == 160 && m[l.planes[1].offset + 17] == 40)
    }

    @Test func jpegRejectsWhatItCannotDecode() {
        let d = ycam_jpeg_new()!
        defer { ycam_jpeg_free(d) }
        var j = flatJPEG(luma: [[1, 2, 3, 4], [5, 6, 7, 8]], cb: [1, 2], cr: [3, 4])
        let truncated = Array(j.prefix(40))
        #expect(ycam_jpeg_decode(d, truncated, truncated.count) == -1)
        if let sof = j.indices.first(where: { j[$0] == 0xFF && j[$0 + 1] == 0xC0 }) { j[sof + 1] = 0xC2 }
        #expect(ycam_jpeg_decode(d, j, j.count) == -2)
        let notJPEG: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0, 0]
        #expect(ycam_jpeg_decode(d, notJPEG, notJPEG.count) == -1)
    }

    @Test func jpegRoundTripThroughLibjpeg() throws {
        try roundTrip()
    }

    func roundTrip() throws {
        guard swiftcodecAvailable() else { return }
        let w = 320, h = 240
        let cam = SyntheticCamera(width: w, height: h, paced: false)
        guard let raw = try cam.next(timeoutMilliseconds: 0) else { Issue.record("no frame"); return }
        let (_, bgraBytes) = try convert(Array(raw.bytes), .yuyv, width: w, height: h, bytesPerLine: raw.bytesPerLine, to: .bgra)
        guard let jpeg = swiftcodecEncode(bgraBytes, width: w, height: h, bytesPerRow: CameraSurfaceLayout.make(.bgra, width: w, height: h).bytesPerRow)
        else { Issue.record("encode failed"); return }
        let (layout, decoded) = try convert(jpeg, .mjpeg, width: w, height: h, bytesPerLine: 0, to: .bgra)
        var total = 0, worst = 0
        for y in 0..<h {
            for x in 0..<w {
                for k in 0..<3 {
                    let a = Int(bgraBytes[y * layout.bytesPerRow + 4 * x + k]), b = Int(decoded[y * layout.bytesPerRow + 4 * x + k])
                    total += abs(a - b)
                    worst = max(worst, abs(a - b))
                }
            }
        }
        let mean = Double(total) / Double(w * h * 3)
        #expect(mean < 4, "mean error \(mean)")
        #expect(worst < 128, "worst error \(worst)")
    }
}

func swiftcodecAvailable() -> Bool { swiftcodec_jpeg_available() != 0 }

func swiftcodecEncode(_ bgra: [UInt8], width: Int, height: Int, bytesPerRow: Int) -> [UInt8]? {
    var out: UnsafeMutablePointer<UInt8>?
    var size = 0
    guard swiftcodec_jpeg_encode_bgra(bgra, Int32(width), Int32(height), bytesPerRow, 95, &out, &size) == 0, let out else { return nil }
    defer { swiftcodec_free(out) }
    return Array(UnsafeBufferPointer(start: out, count: size))
}
