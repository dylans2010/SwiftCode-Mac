import CYcodeXRReprojection
import Foundation
import YcodeDisplayStream

public struct XRReprojectionError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ d: String) { description = d }
}

public final class XRReprojector: @unchecked Sendable {
    public struct Vulkan: @unchecked Sendable {
        public var getInstanceProcAddr: UnsafeMutableRawPointer?
        public var instance: UnsafeMutableRawPointer?
        public var physicalDevice: UnsafeMutableRawPointer?
        public var device: UnsafeMutableRawPointer?
        public var queueFamily: UInt32
        public var queue: UnsafeMutableRawPointer?
        public var anisotropy: Bool
        public init(getInstanceProcAddr: UnsafeMutableRawPointer?, instance: UnsafeMutableRawPointer?, physicalDevice: UnsafeMutableRawPointer?,
                    device: UnsafeMutableRawPointer?, queueFamily: UInt32, queue: UnsafeMutableRawPointer?, anisotropy: Bool = false) {
            (self.getInstanceProcAddr, self.instance, self.physicalDevice, self.device, self.queueFamily, self.queue, self.anisotropy) =
                (getInstanceProcAddr, instance, physicalDevice, device, queueFamily, queue, anisotropy)
        }
    }

    public struct Target: Sendable {
        public var image: UInt64, format: Int64, width: Int, height: Int, depthImage: UInt64
        public init(image: UInt64 = 0, format: Int64 = 0, width: Int, height: Int, depthImage: UInt64 = 0) {
            (self.image, self.format, self.width, self.height, self.depthImage) = (image, format, width, height, depthImage)
        }
    }

    private let context: OpaquePointer
    public let deviceName: String
    public var settings = XRWarpSettings()
    public var fade = 0.04
    public var eyeNear = 0.05
    public var environmentGain = 1.0

    public private(set) var source: XRViewGeometry?
    public private(set) var hasDepth = false
    public private(set) var environmentOrientation: SpatialQuaternion?
    public private(set) var environmentMirrored = false
    public private(set) var environmentCentre: SpatialVector?
    public private(set) var cacheFaceSize = 0
    public var cacheCentre = SpatialVector.zero
    public private(set) var cacheUpdates = 0

    public init(vulkan: Vulkan?) throws {
        var err = [CChar](repeating: 0, count: 512)
        var ctx: OpaquePointer?
        if let v = vulkan {
            var h = yrp_vulkan(get_instance_proc_addr: v.getInstanceProcAddr, instance: v.instance, physical_device: v.physicalDevice,
                               device: v.device, queue_family: v.queueFamily, queue: v.queue, anisotropy: v.anisotropy ? 1 : 0)
            ctx = yrp_create(&h, &err, err.count)
        } else {
            ctx = yrp_create(nil, &err, err.count)
        }
        guard let ctx else { throw XRReprojectionError(String(cString: err)) }
        context = ctx
        deviceName = String(cString: yrp_device_name(ctx))
    }

    deinit { yrp_destroy(context) }

    private func check(_ rc: Int32, _ what: String) throws {
        if rc != 0 { throw XRReprojectionError("\(what): \(String(cString: yrp_error(context)))") }
    }

    public func setPicture(bgra: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int, view: XRViewGeometry) throws {
        try check(yrp_set_colour(context, bgra, Int32(width), Int32(height), Int32(bytesPerRow)), "picture")
        source = view
    }

    public func setPictureYUV(yuv444: Bool, y: UnsafePointer<UInt8>, u: UnsafePointer<UInt8>, v: UnsafePointer<UInt8>?, pitch: Int, width: Int, height: Int, view: XRViewGeometry) throws {
        try check(yrp_set_colour_yuv(context, yuv444 ? Int32(YRP_YUV444) : Int32(YRP_NV12), y, u, v, Int32(pitch), Int32(width), Int32(height)), "picture")
        source = view
    }

    public func readPicture(width: Int, height: Int) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        try check(out.withUnsafeMutableBytes { yrp_read_colour(context, $0.baseAddress, $0.count) }, "read picture")
        return out
    }

    public func setPictureNV12(y: UnsafePointer<UInt8>, uv: UnsafePointer<UInt8>, pitch: Int, width: Int, height: Int, view: XRViewGeometry) throws {
        try check(yrp_set_colour_nv12(context, y, uv, Int32(pitch), Int32(width), Int32(height)), "picture")
        source = view
    }

    public func retag(_ view: XRViewGeometry) { if source != nil { source = view } }

    public func setDepth(_ d: XRDepthImage) throws {
        try d.samples.withUnsafeBufferPointer { try check(yrp_set_depth(context, $0.baseAddress, Int32(d.width), Int32(d.height)), "depth") }
        hasDepth = true
    }

    public func clearDepth() throws {
        var zero: UInt16 = 0
        try check(yrp_set_depth(context, &zero, 1, 1), "depth")
        hasDepth = false
    }

    public func setInset(bgra: UnsafeRawPointer?, width: Int, height: Int, bytesPerRow: Int,
                         rect: (x: Int, y: Int, width: Int, height: Int), fullWidth: Int, fullHeight: Int) throws {
        guard let bgra else { try check(yrp_set_inset(context, nil, 0, 0, 0, 0, 0, 0, 0, 0, 0), "inset"); return }
        try check(yrp_set_inset(context, bgra, Int32(width), Int32(height), Int32(bytesPerRow), Int32(rect.x), Int32(rect.y),
                                Int32(rect.width), Int32(rect.height), Int32(fullWidth), Int32(fullHeight)), "inset")
    }

    public func setEnvironment(faces: [UInt8], halfFloat: Bool, size: Int, orientation: SpatialQuaternion, mirrored: Bool = false) throws {
        try faces.withUnsafeBytes { try check(yrp_set_environment(context, $0.baseAddress, halfFloat ? 1 : 2, Int32(size)), "environment") }
        environmentOrientation = orientation
        environmentMirrored = mirrored
    }

    public func setEnvironmentOrientation(_ o: SpatialQuaternion) { environmentOrientation = o }

    public func setEnvironmentShape(centre: SpatialVector?, depth: [UInt16], n: Int) throws {
        if centre == nil {
            try check(yrp_set_environment_depth(context, nil, 0), "environment shape")
        } else {
            try depth.withUnsafeBufferPointer { try check(yrp_set_environment_depth(context, $0.baseAddress, Int32(n)), "environment shape") }
        }
        environmentCentre = centre
    }

    public func enableCache(faceSize: Int, centre: SpatialVector) throws {
        try check(yrp_cache_enable(context, Int32(faceSize)), "cache")
        cacheFaceSize = faceSize
        cacheCentre = centre
    }

    public func clearCache(centre: SpatialVector? = nil) throws {
        try check(yrp_cache_clear(context), "cache")
        if let centre { cacheCentre = centre }
    }

    private func params(_ m: XRMatrix4, _ src: XRViewGeometry) -> yrp_params {
        var p = yrp_params()
        withUnsafeMutableBytes(of: &p.matrix) { raw in for (i, v) in m.floats.enumerated() { raw.storeBytes(of: v, toByteOffset: i * 4, as: Float.self) } }
        let t = src.fov.tangents
        p.tangents = (Float(t.left), Float(t.right), Float(t.up), Float(t.down))
        p.near_distance = Float(src.near)
        p.edge_ratio = Float(settings.edgeRatio)
        p.grid_step = Int32(settings.gridStep)
        p.mode = settings.mode.rawValue
        return p
    }

    private static func put(_ matrices: [XRMatrix4?], into raw: UnsafeMutableRawBufferPointer) {
        for (f, m) in matrices.enumerated() {
            for (i, v) in (m ?? .identity).floats.enumerated() { raw.storeBytes(of: v, toByteOffset: (f * 16 + i) * 4, as: Float.self) }
        }
    }

    @discardableResult
    public func updateCache() throws -> UInt32 {
        guard cacheFaceSize > 0, let src = source, hasDepth else { return 0 }
        let forward = src.toStage.apply((0, 0, -1, 0))
        let mask = xrVisibleFaces(forward: SpatialVector(forward.x, forward.y, forward.z), fov: src.fov)
        let faces = XRCubeFace.allCases.map { f -> XRMatrix4? in
            mask & (1 << UInt32(f.rawValue)) != 0 ? XRReprojection.matrix(from: src, to: f.geometry(centre: cacheCentre)) : nil
        }
        var p = params(.identity, src)
        var table = [Float](repeating: 0, count: 96)
        table.withUnsafeMutableBytes { Self.put(faces, into: $0) }
        let rc = table.withUnsafeBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: (Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float, Float).self, capacity: 6) {
                yrp_cache_update(context, &p, $0, mask)
            }
        }
        try check(rc, "cache update")
        cacheUpdates += 1
        return mask
    }

    public func render(eye: SpatialPose, fov: XRFieldOfView, target: Target, picture: Bool = true, freshUnder: Bool = false) throws {
        let dst = XRViewGeometry(pose: eye, fov: fov, near: eyeNear)
        var f = yrp_frame()
        if let src = source, picture {
            f.fresh_enabled = 1
            f.fresh = params(XRReprojection.matrix(from: src, to: dst), src)
            f.fade = cacheFaceSize > 0 || environmentOrientation != nil ? Float(fade) : 0
        } else {
            f.fresh = params(.identity, XRViewGeometry(pose: eye, fov: fov))
        }
        let forward = eye.rotation.rotate(SpatialVector(0, 0, -1))
        if let o = environmentOrientation {
            let mask = environmentCentre != nil ? 0x3F : xrVisibleFaces(forward: forward, fov: fov, orientation: o, mirrored: environmentMirrored)
            f.env_mask = mask
            f.env_gain = Float(environmentGain)
            let faces = XRCubeFace.allCases.map { face -> XRMatrix4? in
                mask & (1 << UInt32(face.rawValue)) != 0
                    ? XRReprojection.matrix(from: face.geometry(centre: environmentCentre ?? eye.position, orientation: o, mirrored: environmentMirrored), to: dst) : nil
            }
            withUnsafeMutableBytes(of: &f.env_matrix) { Self.put(faces, into: $0) }
        }
        if cacheFaceSize > 0 {
            let mask = xrVisibleFaces(forward: forward, fov: fov)
            f.cache_mask = mask
            let faces = XRCubeFace.allCases.map { face -> XRMatrix4? in
                mask & (1 << UInt32(face.rawValue)) != 0 ? XRReprojection.matrix(from: face.geometry(centre: cacheCentre), to: dst) : nil
            }
            withUnsafeMutableBytes(of: &f.cache_matrix) { Self.put(faces, into: $0) }
        }
        f.fresh_under = freshUnder ? 1 : 0
        var t = yrp_target(image: target.image, format: target.format, width: UInt32(target.width), height: UInt32(target.height),
                           depth_image: target.depthImage)
        try check(yrp_render(context, &t, &f), "render")
    }

    public func wait() { _ = yrp_wait(context) }

    public func readOffscreen(width: Int, height: Int) throws -> [UInt8] {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        try out.withUnsafeMutableBytes { try check(yrp_read(context, $0.baseAddress, $0.count), "read") }
        return out
    }

    public var gpuMilliseconds: Double? {
        let v = yrp_gpu_ms(context)
        return v >= 0 ? v : nil
    }
}
