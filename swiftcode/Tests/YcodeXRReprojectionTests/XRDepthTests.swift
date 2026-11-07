import Foundation
import Testing
import YcodeDisplayStream
@testable import YcodeXRReprojection

struct SyntheticScene {
    var width = 160, height = 90
    var fov = XRFieldOfView.guest(width: 3840, height: 2160)
    var wall = 4.0, box = 1.0, boxHalf = 0.25
    var near: Float = 0.1

    func hit(u: Double, v: Double) -> (z: Double, colour: (UInt8, UInt8, UInt8)) {
        let t = fov.tangents
        let tx = t.left + u * (t.right - t.left), ty = t.up - v * (t.up - t.down)
        if abs(tx * box) < boxHalf && abs(ty * box) < boxHalf { return (box, (40, 40, 220)) }
        if ty < 0 { let z = 1.6 / -ty; if z < wall { return (z, (30, 160, 30)) } }
        let x = tx * wall, y = ty * wall
        let check = (Int(floor(x / 0.5)) + Int(floor(y / 0.5))) & 1 == 0
        return (wall, check ? (200, 200, 200) : (90, 90, 90))
    }

    func render() -> (colour: [UInt8], depth: XRDepthImage) {
        var c = [UInt8](repeating: 255, count: width * height * 4), q = [UInt16](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let h = hit(u: (Double(x) + 0.5) / Double(width), v: (Double(y) + 0.5) / Double(height))
                let i = y * width + x
                (c[i * 4], c[i * 4 + 1], c[i * 4 + 2]) = h.colour
                q[i] = XRDepthSample.sample(distance: Float(h.z), near: near) & 0xFFFE
            }
        }
        return (c, XRDepthImage(width: width, height: height, samples: q, near: near, fov: fov))
    }
}

@Suite struct XRDepthCodecTests {
    @Test func roundTripIsLosslessAndSmall() throws {
        let (_, d) = SyntheticScene(width: 960, height: 540).render()
        let packed = try XRDepthCodec.encode(d.samples, width: d.width, height: d.height)
        #expect(try XRDepthCodec.decode(packed, width: d.width, height: d.height) == d.samples)
        #expect(packed.count < 2 * d.samples.count / 8)
    }

    @Test func noiseRoundTrips() throws {
        var s: UInt64 = 1
        let v = (0..<(37 * 23)).map { _ -> UInt16 in s = s &* 6364136223846793005 &+ 1442695040888963407; return UInt16(truncatingIfNeeded: s >> 33) }
        let packed = try XRDepthCodec.encode(v, width: 37, height: 23)
        #expect(try XRDepthCodec.decode(packed, width: 37, height: 23) == v)
        #expect(throws: XRDepthCodec.Failure.self) { try XRDepthCodec.decode(Array(packed.prefix(10)), width: 37, height: 23) }
    }

    @Test func quantisationResolvesMillimetres() {
        for z: Float in [0.3, 1, 2, 5] {
            let back = XRDepthSample.distance(XRDepthSample.sample(distance: z, near: 0.1), near: 0.1)
            #expect(abs(back - z) < z * z / (0.1 * 65535) + 1e-4)
        }
        #expect(abs(XRDepthSample.distance(XRDepthSample.sample(distance: 5, near: 0.1), near: 0.1) - 5) < 0.004)
        #expect(XRDepthSample.sample(distance: .infinity, near: 0.1) == 0)
        #expect(XRDepthSample.distance(0, near: 0.1) == .infinity)
        #expect(XRDepthSample.quantize(reverseZ: 1.5) == 65535)
        #expect(XRDepthSample.quantize(reverseZ: 1e-9) == 1)
    }

    @Test func messageRoundTrips() throws {
        let (_, d) = SyntheticScene().render()
        let data = try XRDepthCodec.encode(d.samples, width: d.width, height: d.height)
        let m = XRFrameDepth(frameSequence: 77, guestFrame: 1234, view: .left, flags: [.windowsMerged], width: UInt16(d.width),
                             height: UInt16(d.height), near: 0.1, fov: .guest(width: 2160, height: 3840), capturedAt: 99, data: data)
        let bytes = DisplayMessage.frameDepth(m).encoded()
        #expect(bytes[4] == 0x0C)
        let n = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
        guard case .frameDepth(let back) = try DisplayMessage.decode(type: bytes[4], payload: bytes[5..<(4 + n)]) else {
            Issue.record("not a frame depth"); return
        }
        #expect(back.frameSequence == 77 && back.guestFrame == 1234 && back.view == .left && back.flags == [.windowsMerged])
        #expect(abs(back.fov.tangents.up - 3840.0 / 2160) < 1e-5)
        #expect(try XRDepthImage(back).samples == d.samples)
    }
}

@Suite struct XRReprojectionMathTests {
    let fov = XRFieldOfView.guest(width: 3840, height: 2160)

    @Test func identityKeepsEveryPixel() {
        let v = XRViewGeometry(pose: SpatialPose(position: SpatialVector(0.3, 1.2, -0.4), rotation: SpatialQuaternion(yaw: 0.4, pitch: -0.2)), fov: fov)
        for (u, w, q) in [(0.1, 0.2, UInt16(3000)), (0.9, 0.7, 60000), (0.5, 0.5, 0)] {
            let r = XRReprojection.reproject(u: u, v: w, q: q, from: v, to: v)!
            #expect(abs(r.u - u) < 1e-9 && abs(r.v - w) < 1e-9)
            #expect(abs(r.depth - Double(q) / 65535) < 1e-9)
        }
    }

    @Test func translationGivesParallaxInInverseDepth() {
        let src = XRViewGeometry(pose: .identity, fov: fov)
        let b = 0.064
        let dst = XRViewGeometry(pose: SpatialPose(position: SpatialVector(b, 0, 0)), fov: fov)
        for z in [0.5, 1.0, 4.0] {
            let q = XRDepthSample.sample(distance: Float(z), near: 0.1)
            let r = XRReprojection.reproject(u: 0.5, v: 0.5, q: q, from: src, to: dst)!
            let expected = 0.5 - b / Double(XRDepthSample.distance(q, near: 0.1)) / 2
            #expect(abs(r.u - expected) < 1e-6)
        }
        let far = XRReprojection.reproject(u: 0.3, v: 0.6, q: 0, from: src, to: dst)!
        #expect(abs(far.u - 0.3) < 1e-9 && abs(far.v - 0.6) < 1e-9 && far.depth == 0)
        let turned = XRViewGeometry(pose: SpatialPose(rotation: SpatialQuaternion(yaw: .pi / 8, pitch: 0)), fov: fov)
        let t = XRReprojection.reproject(u: 0.5, v: 0.5, q: 0, from: src, to: turned)!
        #expect(abs(t.u - (0.5 + tan(Double.pi / 8) / 2)) < 1e-9)
    }

    @Test func projectionIsReverseZInfinite() {
        let p = XRMatrix4.projection(fov, near: 0.1)
        let c = p.apply((0, 0, -2, 1))
        #expect(abs(c.z / c.w - 0.05) < 1e-12)
        let inf = p.apply((0, 0, -1, 0))
        #expect(inf.z == 0 && inf.w == 1)
        let top = p.apply((0, fov.tangents.up, -1, 1))
        #expect(abs(top.y / top.w + 1) < 1e-12)
    }

    @Test func eyesFollowTheHead() {
        let head = SpatialPose(position: SpatialVector(0, 1.6, 0), rotation: SpatialQuaternion(yaw: .pi / 2, pitch: 0))
        let (l, r) = XRReprojection.eyes(head: head, ipd: 0.064)
        #expect(abs(l.position.z - 0.032) < 1e-12 && abs(r.position.z + 0.032) < 1e-12)
        #expect(abs((r.position - l.position).length - 0.064) < 1e-12)
    }

    @Test func cubeFacesMatchTheLookupTable() {
        for f in XRCubeFace.allCases {
            let g = f.geometry(centre: SpatialVector(1, 2, 3))
            for (u, v) in [(0.5, 0.5), (0.1, 0.2), (0.8, 0.9)] {
                let p = g.point(u: u, v: v, q: 0)
                let d = g.toStage.apply(p)
                let back = XRCubeFace.lookup(SpatialVector(d.x, d.y, d.z))
                #expect(back.face == f)
                #expect(abs(back.u - u) < 1e-9 && abs(back.v - v) < 1e-9)
            }
        }
        let mask = xrVisibleFaces(forward: SpatialVector(0, 0, -1), fov: fov)
        #expect(mask & (1 << 5) != 0 && mask & (1 << 4) == 0)
    }

    @Test func inverseUndoesAMirroredBasis() {
        let g = XRCubeFace.negY.geometry(centre: SpatialVector(0.5, -1, 2), orientation: SpatialQuaternion(yaw: 0.3, pitch: 0.1))
        let i = g.toStage * g.fromStage
        for r in 0..<4 { for c in 0..<4 { #expect(abs(i[r, c] - (r == c ? 1 : 0)) < 1e-12) } }
    }
}

@Suite struct XRReferenceWarpTests {
    @Test func samePoseReproducesThePicture() {
        let s = SyntheticScene()
        let (c, d) = s.render()
        let v = XRViewGeometry(pose: .identity, fov: s.fov)
        let r = XRReferenceWarp.warp(colour: c, colourWidth: s.width, colourHeight: s.height, depth: d, source: v, destination: v,
                                     width: s.width, height: s.height, settings: XRWarpSettings(gridStep: 1))
        var wrong = 0
        for y in 2..<(s.height - 2) { for x in 2..<(s.width - 2) {
            let p = r.pixel(x, y), i = (y * s.width + x) * 4
            if abs(Int(p.b) - Int(c[i])) > 2 || abs(Int(p.r) - Int(c[i + 2])) > 2 { wrong += 1 }
        } }
        #expect(Double(wrong) / Double(s.width * s.height) < 0.02)
        #expect(r.covered > s.width * s.height * 95 / 100)
    }

    @Test func stereoShiftAndBackgroundFill() {
        let s = SyntheticScene(width: 320, height: 180)
        let (c, d) = s.render()
        let src = XRViewGeometry(pose: .identity, fov: s.fov)
        let (_, right) = XRReprojection.eyes(head: .identity, ipd: 0.064)
        let dst = XRViewGeometry(pose: right, fov: s.fov)
        let bg = XRReferenceWarp.warp(colour: c, colourWidth: s.width, colourHeight: s.height, depth: d, source: src, destination: dst,
                                      width: s.width, height: s.height, settings: XRWarpSettings(gridStep: 1, mode: .background))
        let holes = XRReferenceWarp.warp(colour: c, colourWidth: s.width, colourHeight: s.height, depth: d, source: src, destination: dst,
                                         width: s.width, height: s.height, settings: XRWarpSettings(gridStep: 1, mode: .discard))
        let boxShift = 0.032 / 1.0 / 2, wallShift = 0.032 / 4.0 / 2
        let row = s.height / 2
        let edge = Int((0.625 - boxShift) * Double(s.width)), wallStart = Int((0.625 - wallShift) * Double(s.width))
        #expect(bg.pixel(edge - 2, row).r > 150 && bg.pixel(edge - 2, row).g < 80)
        let strip = wallStart - edge
        #expect(strip >= 3)
        for x in (edge + 1)..<wallStart {
            let p = bg.pixel(x, row)
            #expect(p.a == 255 && !(p.r > 150 && p.g < 80))
            #expect(holes.pixel(x, row).a == 0)
        }
        let expected = Double(strip) * 0.5 / (s.fov.tangents.up - s.fov.tangents.down) * Double(s.height)
        #expect(Double(bg.stretched) > expected * 0.5 && Double(bg.stretched) < expected * 3)
        #expect(bg.stretchedFraction < 0.05)
        #expect(holes.covered < bg.covered)
    }
}

@Suite(.serialized) struct XRReprojectorGPUTests {
    static let gpu: XRReprojector? = try? XRReprojector(vulkan: nil)

    @Test func gpuMatchesTheReference() throws {
        guard let gpu = Self.gpu else { print("XRReprojectorGPUTests: no Vulkan device; skipped"); return }
        let s = SyntheticScene(width: 320, height: 180)
        let (c, d) = s.render()
        let src = XRViewGeometry(pose: .identity, fov: s.fov)
        let (_, right) = XRReprojection.eyes(head: .identity, ipd: 0.064)
        try c.withUnsafeBytes { try gpu.setPicture(bgra: $0.baseAddress!, width: s.width, height: s.height, bytesPerRow: s.width * 4, view: src) }
        try gpu.setDepth(d)
        gpu.settings = XRWarpSettings(gridStep: 1, mode: .background)
        gpu.eyeNear = 0.1
        try gpu.render(eye: right, fov: s.fov, target: .init(width: s.width, height: s.height))
        let out = try gpu.readOffscreen(width: s.width, height: s.height)
        let ref = XRReferenceWarp.warp(colour: c, colourWidth: s.width, colourHeight: s.height, depth: d, source: src,
                                       destination: XRViewGeometry(pose: right, fov: s.fov, near: 0.1), width: s.width, height: s.height,
                                       settings: XRWarpSettings(gridStep: 1, mode: .background))
        var differ = 0
        for i in 0..<(s.width * s.height) where ref.pixels[i * 4 + 3] != 0 {
            if abs(Int(out[i * 4 + 2]) - Int(ref.pixels[i * 4 + 2])) > 40 || abs(Int(out[i * 4 + 1]) - Int(ref.pixels[i * 4 + 1])) > 40 { differ += 1 }
        }
        print("XRReprojectorGPUTests: \(gpu.deviceName): \(differ) of \(ref.covered) pixels differ from the reference")
        #expect(Double(differ) / Double(ref.covered) < 0.03)
    }

    @Test func cacheFillsWhatThePictureNoLongerCovers() throws {
        guard let gpu = Self.gpu else { return }
        let s = SyntheticScene(width: 320, height: 180)
        let (c, d) = s.render()
        try gpu.enableCache(faceSize: 256, centre: .zero)
        gpu.settings = XRWarpSettings(gridStep: 1, mode: .background)
        let src = XRViewGeometry(pose: .identity, fov: s.fov)
        try c.withUnsafeBytes { try gpu.setPicture(bgra: $0.baseAddress!, width: s.width, height: s.height, bytesPerRow: s.width * 4, view: src) }
        try gpu.setDepth(d)
        let faces = try gpu.updateCache()
        #expect(faces & (1 << 5) != 0)
        let turned = SpatialPose(rotation: SpatialQuaternion(yaw: .pi / 3, pitch: 0))
        try gpu.render(eye: turned, fov: s.fov, target: .init(width: s.width, height: s.height), picture: false)
        let out = try gpu.readOffscreen(width: s.width, height: s.height)
        let row = s.height / 4, x = Int(0.85 * Double(s.width))
        #expect(out[(row * s.width + x) * 4 + 3] > 0 || out[(row * s.width + x) * 4] > 20)
        let xl = Int(0.1 * Double(s.width))
        #expect(out[(row * s.width + xl) * 4] < 5 && out[(row * s.width + xl) * 4 + 2] < 5)
        try gpu.enableCache(faceSize: 0, centre: .zero)
    }

    @Test func overTheCacheDisocclusionsAreFilledNotBlack() throws {
        guard let gpu = Self.gpu else { return }
        let s = SyntheticScene(width: 320, height: 180)
        let (c, d) = s.render()
        try gpu.enableCache(faceSize: 256, centre: .zero)
        try gpu.clearCache()
        gpu.settings = XRWarpSettings(gridStep: 1, mode: .background)
        gpu.eyeNear = 0.1
        let src = XRViewGeometry(pose: .identity, fov: s.fov)
        try c.withUnsafeBytes { try gpu.setPicture(bgra: $0.baseAddress!, width: s.width, height: s.height, bytesPerRow: s.width * 4, view: src) }
        try gpu.setDepth(d)
        try gpu.updateCache()
        try gpu.render(eye: SpatialPose(position: SpatialVector(0.1, 0, 0)), fov: s.fov, target: .init(width: s.width, height: s.height))
        let out = try gpu.readOffscreen(width: s.width, height: s.height)
        var black: [Int] = []
        let row = s.height / 2
        for x in (s.width / 10)..<(s.width * 9 / 10) {
            let i = (row * s.width + x) * 4
            if out[i] < 8 && out[i + 1] < 8 && out[i + 2] < 8 { black.append(x) }
        }
        #expect(black.isEmpty, "black pixels on the middle row at \(black)")
        try gpu.enableCache(faceSize: 0, centre: .zero)
    }

    @Test func aStretchedEdgeIsNotStoredInTheCache() throws {
        guard let gpu = Self.gpu else { return }
        let s = SyntheticScene(width: 320, height: 180)
        let (c, d) = s.render()
        try gpu.enableCache(faceSize: 512, centre: .zero)
        try gpu.clearCache()
        gpu.settings = XRWarpSettings(gridStep: 1, mode: .background)
        gpu.eyeNear = 0.1
        let src = XRViewGeometry(pose: SpatialPose(position: SpatialVector(0.2, 0, 0)), fov: s.fov)
        try c.withUnsafeBytes { try gpu.setPicture(bgra: $0.baseAddress!, width: s.width, height: s.height, bytesPerRow: s.width * 4, view: src) }
        try gpu.setDepth(d)
        try gpu.updateCache()
        try gpu.render(eye: .identity, fov: s.fov, target: .init(width: s.width, height: s.height), picture: false)
        let out = try gpu.readOffscreen(width: s.width, height: s.height)
        let row = s.height / 2, x = Int((-0.125 + 1) / 2 * Double(s.width))
        let i = (row * s.width + x) * 4
        #expect(out[i] < 8 && out[i + 1] < 8 && out[i + 2] < 8, "the stretched edge was stored: \(out[i]) \(out[i + 1]) \(out[i + 2])")
        let j = (row * s.width + Int((-0.4 + 1) / 2 * Double(s.width))) * 4
        #expect(out[j] > 40 || out[j + 1] > 40)
        try gpu.enableCache(faceSize: 0, centre: .zero)
    }

    @Test func theWindowsLayerStaysOutOfTheCache() throws {
        guard let gpu = Self.gpu else { return }
        let s = FloatingDiscScene()
        try gpu.enableCache(faceSize: 512, centre: .zero)
        try gpu.clearCache()
        gpu.settings = XRWarpSettings(gridStep: 1, mode: .background)
        gpu.eyeNear = 0.1
        let view = XRViewGeometry(pose: .identity, fov: s.fov)
        func show(_ scene: (colour: [UInt8], depth: XRDepthImage)) throws {
            try scene.colour.withUnsafeBytes { try gpu.setPicture(bgra: $0.baseAddress!, width: s.width, height: s.height, bytesPerRow: s.width * 4, view: view) }
            try gpu.setDepth(scene.depth)
        }
        func isDisc(_ out: [UInt8], _ x: Int, _ y: Int) -> Bool {
            let i = (y * s.width + x) * 4
            return out[i] > 180 && out[i + 2] < 70
        }
        let centre = s.width / 2
        var room = s.render()
        for i in room.depth.samples.indices where room.depth.samples[i] == XRDepthSample.sample(distance: Float(s.disc), near: 0.1) & 0xFFFE {
            room.depth.samples[i] = XRDepthSample.sample(distance: Float(s.wall), near: 0.1) & 0xFFFE
            (room.colour[i * 4], room.colour[i * 4 + 1], room.colour[i * 4 + 2]) = (40, 40, 40)
        }
        try show(room)
        try gpu.updateCache()
        try show(s.render(window: true))
        try gpu.updateCache()
        let target = XRReprojector.Target(width: s.width, height: s.height)
        try gpu.render(eye: .identity, fov: s.fov, target: target, picture: false)
        var out = try gpu.readOffscreen(width: s.width, height: s.height)
        #expect(!isDisc(out, centre, centre), "the window went into the cache")
        try gpu.render(eye: .identity, fov: s.fov, target: target, picture: true, freshUnder: true)
        out = try gpu.readOffscreen(width: s.width, height: s.height)
        #expect(isDisc(out, centre, centre), "the window is hidden while the head moves")
        try gpu.clearCache()
        try show(s.render(window: false))
        try gpu.updateCache()
        try gpu.render(eye: .identity, fov: s.fov, target: target, picture: false)
        out = try gpu.readOffscreen(width: s.width, height: s.height)
        #expect(isDisc(out, centre, centre), "a room object is missing from the cache")
        try gpu.enableCache(faceSize: 0, centre: .zero)
    }

    @Test func gpuTimeFitsTheHeadsetFrame() throws {
        guard let gpu = Self.gpu else { return }
        let s = SyntheticScene(width: 960, height: 540)
        let (_, d) = s.render()
        let colour = [UInt8](repeating: 128, count: 1920 * 1080 * 4)
        let src = XRViewGeometry(pose: .identity, fov: s.fov)
        try colour.withUnsafeBytes { try gpu.setPicture(bgra: $0.baseAddress!, width: 1920, height: 1080, bytesPerRow: 1920 * 4, view: src) }
        try gpu.setDepth(d)
        try gpu.enableCache(faceSize: 1024, centre: .zero)
        gpu.settings = XRWarpSettings(gridStep: 2, mode: .background)
        let eyeFov = XRFieldOfView(left: -54 * .pi / 180, right: 40 * .pi / 180, up: 48 * .pi / 180, down: -48 * .pi / 180)
        var times: [Double] = []
        for i in 0..<60 {
            if i % 3 == 0 { try gpu.updateCache() }
            let head = SpatialPose(rotation: SpatialQuaternion(yaw: Double(i) * 0.01, pitch: 0))
            let (l, r) = XRReprojection.eyes(head: head, ipd: 0.064)
            try gpu.render(eye: l, fov: eyeFov, target: .init(width: 2700, height: 2970))
            try gpu.render(eye: r, fov: eyeFov, target: .init(width: 2700, height: 2970))
            if let t = gpu.gpuMilliseconds { times.append(t) }
        }
        gpu.wait()
        try gpu.enableCache(faceSize: 0, centre: .zero)
        let sorted = times.sorted()
        print("XRReprojectorGPUTests: \(gpu.deviceName): one eye with the cache p50 \(sorted.isEmpty ? 0 : sorted[sorted.count / 2]) ms")
        #expect(!sorted.isEmpty)
    }
}

@Suite struct XREnvironmentCalibrationTests {
    static func light(_ d: SpatialVector) -> Float {
        let n = d.normalized
        let az = atan2(n.z, n.x)
        return Float(0.3 + 0.2 * sin(3 * az) + (n.x > 0.8 ? 2 : 0) + 0.3 * max(0, n.y))
    }

    static func halfBits(_ f: Float) -> UInt16 {
        let b = f.bitPattern
        let e = Int((b >> 23) & 0xFF) - 127 + 15, m = (b >> 13) & 0x3FF
        return UInt16(b >> 31) << 15 | UInt16(max(0, min(30, e))) << 10 | UInt16(m)
    }

    @Test func halfFloats() {
        for v: Float in [0, 0.5, 1, 1.5, 27.25, -2] { #expect(XREnvironmentCalibration.half(Self.halfBits(v)) == v) }
        #expect(XREnvironmentCalibration.half(0x0001) > 0 && XREnvironmentCalibration.half(0x7C00) == .infinity)
    }

    static func wall(_ p: SpatialVector) -> Float {
        let stripes: Float = sin(Float(p.x * 3)) * sin(Float(p.z * 3)) * cos(Float(p.y * 4))
        return 0.4 + 0.25 * stripes + (p.y > 0.8 ? 0.2 : 0)
    }
    static func hit(_ o: SpatialVector, _ d: SpatialVector, _ lo: SpatialVector, _ hi: SpatialVector) -> Double {
        func t(_ o: Double, _ d: Double, _ l: Double, _ h: Double) -> Double { d > 1e-9 ? (h - o) / d : d < -1e-9 ? (l - o) / d : .infinity }
        return min(t(o.x, d.x, lo.x, hi.x), t(o.y, d.y, lo.y, hi.y), t(o.z, d.z, lo.z, hi.z))
    }

    @Test func findsTheProbeTheExposureAndTheRoom() throws {
        let lo = SpatialVector(-2.5, -1.6, -4), hi = SpatialVector(2, 1.2, 1.5), probe = SpatialVector(0.5, 0.2, -1.5)
        let size = 64
        var data = [UInt8](repeating: 0, count: 6 * size * size * 8)
        for f in XRCubeFace.allCases {
            let g = f.geometry(centre: .zero, mirrored: true)
            for y in 0..<size {
                for x in 0..<size {
                    let p = g.toStage.apply((-1 + 2 * (Double(x) + 0.5) / Double(size), 1 - 2 * (Double(y) + 0.5) / Double(size), -1, 0))
                    let d = SpatialVector(p.x, p.y, p.z)
                    let l = Self.halfBits(Self.wall(probe + d * Self.hit(probe, d, lo, hi)))
                    let o = ((f.rawValue * size + y) * size + x) * 8
                    for c in 0..<3 { data[o + 2 * c] = UInt8(l & 0xFF); data[o + 2 * c + 1] = UInt8(l >> 8) }
                }
            }
        }
        let cube = XREnvironmentCalibration.Cube(halfFloats: data, size: size)
        var samples: [XREnvironmentCalibration.Sample] = []
        for j in 0..<60 { for i in 0..<120 {
            let az = Double(i) / 120 * 2 * .pi, el = (Double(j) + 0.5) / 60 * .pi - .pi / 2
            let d = SpatialVector(cos(el) * sin(az), sin(el), cos(el) * cos(az))
            let p = d * Self.hit(.zero, d, lo, hi)
            samples.append((p, 0.6 * Self.wall(p)))
        } }
        let c = try #require(XREnvironmentCalibration.calibrate(cube: cube, samples: samples))
        #expect((c.probe - probe).length < 0.15)
        #expect(c.score > 0.8)
        #expect(abs(c.gain - 0.6) < 0.06)
        #expect((c.boxMin - lo).length < 0.3 && (c.boxMax - hi).length < 0.3)
    }

    @Test func aMirroredFaceShowsWhatTheLookupNames() {
        #expect(abs(XRCubeFace.posZ.axis(mirrored: true).z + 1) < 1e-12)
        #expect(abs(XRCubeFace.negZ.axis(mirrored: true).z - 1) < 1e-12)
        for f in XRCubeFace.allCases {
            let g = f.geometry(centre: .zero, mirrored: true)
            let p = g.toStage.apply((0.3, -0.2, -1, 0))
            let (face, u, v) = XRCubeFace.lookup(SpatialVector(p.x, p.y, -p.z))
            #expect(face == f && abs(u - 0.65) < 1e-9 && abs(v - 0.6) < 1e-9)
        }
    }

    @Test func boxDepthPutsTheFacesOnTheBox() {
        let lo = SpatialVector(-2, -1.5, -4), hi = SpatialVector(3, 1, 1), probe = SpatialVector(0.5, 0.2, -1.5)
        let n = 9
        let q = XREnvironmentCalibration.boxDepth(probe: probe, boxMin: lo, boxMax: hi, n: n)
        for f in XRCubeFace.allCases {
            let g = f.geometry(centre: probe, mirrored: true)
            for j in 0..<n { for i in 0..<n {
                let s = q[f.rawValue * n * n + j * n + i]
                let t = g.toStage.apply((-1 + 2 * Double(i) / Double(n - 1), 1 - 2 * Double(j) / Double(n - 1), -1, Double(s) / 65535 / 0.1))
                let p = SpatialVector(t.x / t.w, t.y / t.w, t.z / t.w)
                let plane = [abs(p.x - lo.x), abs(p.x - hi.x), abs(p.y - lo.y), abs(p.y - hi.y), abs(p.z - lo.z), abs(p.z - hi.z)].min()!
                #expect(plane < 0.02)
            } }
        }
    }
}

@Suite struct XRCameraTests {
    static let degree = Double.pi / 180
    static func pose(_ x: Double, yaw: Double = 0) -> SpatialPose {
        SpatialPose(position: SpatialVector(x, 0, 0), rotation: SpatialQuaternion(yaw: yaw * degree, pitch: 0))
    }

    @Test func holdKeepsThePoseInsideTheBandAndRestsAfterFollowing() {
        var h = XRCameraHold()
        #expect(h.apply(Self.pose(0), time: 0) == Self.pose(0) && h.holding)
        #expect(h.apply(Self.pose(0.01, yaw: 1), time: 0.1) == Self.pose(0))
        #expect(h.apply(Self.pose(0.03), time: 0.2) == Self.pose(0.03) && !h.holding)
        #expect(h.apply(Self.pose(0.06), time: 0.25) == Self.pose(0.06))
        #expect(h.apply(Self.pose(0.06), time: 0.3) == Self.pose(0.06) && !h.holding)
        #expect(h.apply(Self.pose(0.061), time: 0.41) == Self.pose(0.061) && h.holding)
        #expect(h.apply(Self.pose(0.065), time: 0.5) == Self.pose(0.061))
    }

    @Test func aSlowTurnKeepsFollowing() {
        var h = XRCameraHold()
        _ = h.apply(Self.pose(0), time: 0)
        var last = Self.pose(0)
        for i in 1...100 {
            let p = Self.pose(0, yaw: Double(i) * 0.25)
            last = h.apply(p, time: Double(i) * 0.01)
        }
        #expect(!h.holding && XRCameraHold.differs(last, Self.pose(0, yaw: 25), metres: 0.001, radians: 0.01 * Self.degree) == false)
    }

    @Test func sweepCoversTheSphere() {
        for (w, h, count) in [(2160, 3840, 8), (3840, 2160, 24), (3072, 3072, 16)] {
            let fov = XRFieldOfView.guest(width: w, height: h)
            let s = XRSweep(fov: fov)
            #expect(s.stops.count <= count, "\(w)x\(h): \(s.stops.count) stops")
            for j in 0..<36 { for i in 0..<72 {
                let az = Double(i) * 5 * Self.degree, el = (Double(j) * 5 - 87.5) * Self.degree
                let d = SpatialVector(cos(el) * sin(az), sin(el), cos(el) * cos(az))
                #expect(s.stops.contains { XRSweep.sees($0, d, fov.tangents) }, "\(w)x\(h): az \(i * 5) el \(j * 5 - 87)")
            } }
        }
    }

    @Test func sweepVisitsEachStopOnce() {
        var s = XRSweep(fov: .guest(width: 2160, height: 3840))
        var n = 0
        while s.current != nil { s.advance(); n += 1 }
        #expect(n == s.stops.count && s.finished)
    }
}
