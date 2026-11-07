import CVulkan
import Foundation
import SwiftCodeMetalHost

public struct XRDepthCapture: Sendable {
    public var serial: UInt64
    public var width: Int, height: Int
    public var samples: [UInt16]
    public var roomPasses: Int, windowsPasses: Int
    public var recordedAt: UInt64
}

public struct XREnvironmentCapture: Sendable {
    public var serial: UInt64
    public var size: Int
    public var level: Int
    public var halfFloats: [UInt8]
    public var hash: UInt64
}

public final class XRDepthTap: @unchecked Sendable {
    public static let shared = XRDepthTap()

    private let lock = NSLock()
    private var downscale = 0
    private var wantsEnvironment = false
    fileprivate var surfaceSerials: [UInt32: UInt64] = [:]
    fileprivate var captures: [XRDepthCapture] = []
    fileprivate var environment: XREnvironmentCapture?
    fileprivate var counters = (passes: 0, captures: 0, dispatches: 0, forcedStores: 0)
    static let log = ProcessInfo.processInfo.environment["SWIFTCODE_XR_DEPTH_LOG"] == "1"
    static let windows = ProcessInfo.processInfo.environment["SWIFTCODE_XR_DEPTH_WINDOWS"] != "0"
    static let windowsAlphaMin = Float(ProcessInfo.processInfo.environment["SWIFTCODE_XR_DEPTH_ALPHA"] ?? "") ?? 0.25

    public func request(downscale n: Int) { lock.withLock { downscale = n > 0 ? min(16, n) : 0 } }
    public func request(environment on: Bool) { lock.withLock { wantsEnvironment = on } }

    var currentDownscale: Int { lock.withLock { downscale } }
    var environmentWanted: Bool { lock.withLock { wantsEnvironment } }

    public func depth(forSurface surface: UInt32) -> (capture: XRDepthCapture, exact: Bool)? {
        lock.withLock {
            if let s = surfaceSerials[surface], let c = captures.last(where: { $0.serial == s }) { return (c, true) }
            return captures.last.map { ($0, false) }
        }
    }

    public func newestEnvironment() -> XREnvironmentCapture? { lock.withLock { environment } }

    public var summary: String {
        lock.withLock { "depth tap: \(counters.passes) candidate passes, \(counters.dispatches) reductions, \(counters.captures) captures, \(counters.forcedStores) depth stores kept" }
    }

    fileprivate func publish(_ c: XRDepthCapture) {
        lock.withLock {
            captures.append(c)
            if captures.count > 6 { captures.removeFirst(captures.count - 6) }
            counters.captures += 1
        }
    }

    fileprivate func note(_ f: (inout (passes: Int, captures: Int, dispatches: Int, forcedStores: Int)) -> Void) { lock.withLock { f(&counters) } }
}

final class DepthTapState {
    struct Slot {
        var buffer = yvk_buffer()
        var bytes = 0
        var serial: UInt64 = 0
        var width = 0, height = 0
        var roomPasses = 0, windowsPasses = 0
        var recordedAt: UInt64 = 0
        var published = false
    }
    var pipeline: VkPipeline?
    var failed = false
    var slots: [Slot] = Array(repeating: Slot(), count: 4)
    var next = 0
    var serial: UInt64 = 0
    var current: Int?
    struct View { weak var image: VKImage?; var view: VkImageView?; var slot: UInt32 }
    var views: [ObjectIdentifier: View] = [:]
    var imageSerials: [ObjectIdentifier: UInt64] = [:]
    weak var cube: VKTexture?
    var cubeBuffer = yvk_buffer()
    var cubeBytes = 0
    var cubeSerial: UInt64 = 0
    var cubeLevel = 0
    var cubeCopyPending = false
    var nextCubeCopy: UInt64 = 0
    var envSerial: UInt64 = 0
    var envHash: UInt64 = 0
    var logged = 0
}

struct DepthTapPass {
    var texture: VKTexture
    var width: Int, height: Int
    var multisampled: Bool
    var standardZ: Bool
    var alpha: VKTexture?
}

extension VulkanMetalBackend {
    var tap: DepthTapState {
        if let t = depthTapStorage as? DepthTapState { return t }
        let t = DepthTapState()
        depthTapStorage = t
        return t
    }

    func depthTapDeviceLost(_ device: VkDevice?) {
        guard let t = depthTapStorage as? DepthTapState else { return }
        if let p = t.pipeline { fn.vkDestroyPipeline!(device, p, nil) }
        for v in t.views.values {
            if let view = v.view { fn.vkDestroyImageView!(device, view, nil) }
            textureIndices.release(v.slot, count: 1)
        }
        for i in t.slots.indices where t.slots[i].buffer.buffer != nil { yvk_buffer_destroy(ctx, &t.slots[i].buffer) }
        if t.cubeBuffer.buffer != nil { yvk_buffer_destroy(ctx, &t.cubeBuffer) }
        let cube = t.cube
        let fresh = DepthTapState()
        fresh.cube = cube
        fresh.serial = t.serial
        fresh.envSerial = t.envSerial
        fresh.envHash = t.envHash
        depthTapStorage = fresh
        log("depth tap: reset with the device")
    }

    func depthTapBegin(_ mcb: MetalCommandBuffer) {
        guard XRDepthTap.shared.currentDownscale > 0 || XRDepthTap.shared.environmentWanted || depthTapStorage != nil else { return }
        let t = tap
        t.current = nil
        collectFinishedCaptures(t)
    }

    func depthTapEnd(_ mcb: MetalCommandBuffer, _ rec: Recording) {
        guard let t = depthTapStorage as? DepthTapState else { return }
        var serial: UInt64?
        if let i = t.current {
            barrier(rec.cb)
            var s = t.slots[i].serial
            fn.vkCmdUpdateBuffer!(rec.cb, t.slots[i].buffer.buffer, VkDeviceSize(t.slots[i].bytes), 8, &s)
            yvk_cmd_memory_barrier(rec.cb, allCommands, memoryWrite, VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT)
            serial = s
            t.current = nil
        }
        depthTapProvenance(mcb, serial: serial, t)
        if XRDepthTap.shared.environmentWanted { environmentCopy(rec, t) }
    }

    func depthTapPassBegin(_ d: MetalRenderPassDescriptor, _ info: inout yvk_rendering_info, width: Int, height: Int,
                           draws: Bool) -> DepthTapPass? {
        guard draws, XRDepthTap.shared.currentDownscale > 0, width >= 1024, height >= 576,
              let a = d.depth, let h = a.texture, let tex = textures[h], tex.format.isDepth, a.level == 0 else { return nil }
        let t = tap
        guard !t.failed else { return nil }
        let multisampled = tex.image.samples > 1
        if multisampled && !XRDepthTap.windows { return nil }
        if multisampled && !d.colorAttachments.contains(where: { $0.attachment.resolveTexture != nil }) { return nil }
        XRDepthTap.shared.note { $0.passes += 1 }
        if info.depth.store != VK_ATTACHMENT_STORE_OP_STORE {
            info.depth.store = VK_ATTACHMENT_STORE_OP_STORE
            XRDepthTap.shared.note { $0.forcedStores += 1 }
        }
        let standardZ = a.loadAction == MetalLoadAction.clear && d.clearDepth > 0.5
        if XRDepthTap.log && t.logged < 40 {
            t.logged += 1
            log("depth tap: pass \(width)x\(height) depth format \(tex.metalFormat) samples \(tex.image.samples) load \(a.loadAction) store \(a.storeAction) clear \(d.clearDepth) colours \(d.colorAttachments.count) resolve \(d.colorAttachments.contains { $0.attachment.resolveTexture != nil }) process \(debugReplayProcess)")
        }
        var alpha: VKTexture?
        if multisampled, XRDepthTap.windowsAlphaMin > 0,
           let c = d.colorAttachments.first(where: { $0.attachment.resolveTexture != nil }), c.attachment.level == 0,
           let r = c.attachment.resolveTexture, let rt = textures[r],
           rt.image.width == tex.image.width, rt.image.height == tex.image.height, rt.image.samples == 1 {
            alpha = rt
        }
        return DepthTapPass(texture: tex, width: width, height: height, multisampled: multisampled, standardZ: standardZ, alpha: alpha)
    }

    func depthTapPassEnd(_ p: DepthTapPass, _ rec: Recording) {
        let t = tap
        let n = XRDepthTap.shared.currentDownscale
        guard n > 0, let pipeline = tapPipeline(t), let slotIndex = tapView(p.texture, t) else { return }
        let alphaSlot = p.alpha.flatMap { tapView($0, t) }
        let ow = (p.width + n - 1) / n, oh = (p.height + n - 1) / n
        let bytes = ((ow + 1) / 2) * 4 * oh
        var merge = false
        if let i = t.current, t.slots[i].width == ow, t.slots[i].height == oh, t.slots[i].bytes >= bytes {
            merge = p.multisampled
        } else {
            guard let i = tapSlot(t, bytes: bytes) else { return }
            t.current = i
            t.serial += 1
            t.slots[i].serial = t.serial
            t.slots[i].width = ow
            t.slots[i].height = oh
            t.slots[i].roomPasses = 0
            t.slots[i].windowsPasses = 0
            t.slots[i].recordedAt = DispatchTime.now().uptimeNanoseconds
        }
        let i = t.current!
        if p.multisampled { t.slots[i].windowsPasses += 1 } else { t.slots[i].roomPasses += 1 }
        barrier(rec.cb)
        fn.vkCmdBindPipeline!(rec.cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline)
        rec.heapBoundCompute = false
        bindHeap(rec, graphics: false)
        let address = t.slots[i].buffer.address
        var pc: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, Float) =
            (UInt32(truncatingIfNeeded: address), UInt32(truncatingIfNeeded: address >> 32), slotIndex,
             UInt32(p.texture.image.width), UInt32(p.texture.image.height), UInt32(ow), UInt32(oh), UInt32(n),
             (p.standardZ ? 1 : 0) | (p.multisampled ? 2 : 0) | (merge ? 4 : 0) | (alphaSlot != nil ? 8 : 0),
             alphaSlot ?? 0, XRDepthTap.windowsAlphaMin)
        fn.vkCmdPushConstants!(rec.cb, ctx.pointee.pipelineLayout, VK_SHADER_STAGE_ALL.rawValue, 0,
                               UInt32(MemoryLayout.size(ofValue: pc)), &pc)
        fn.vkCmdDispatch!(rec.cb, UInt32(((ow + 1) / 2 + 7) / 8), UInt32((oh + 7) / 8), 1)
        barrier(rec.cb)
        XRDepthTap.shared.note { $0.dispatches += 1 }
    }

    private func tapPipeline(_ t: DepthTapState) -> VkPipeline? {
        if let p = t.pipeline { return p }
        var err = [CChar](repeating: 0, count: 512)
        let p: VkPipeline? = depthTapSPIRV.withUnsafeBufferPointer { words in
            "main".withCString { name in
                var stage = yvk_shader_stage(code: words.baseAddress, wordCount: words.count, entry: name, constants: nil, constantCount: 0, flags: 0)
                return yvk_compute_pipeline_create(ctx, &stage, &err, err.count)
            }
        }
        if p == nil { t.failed = true; log("depth tap: pipeline: \(cString(err))") }
        t.pipeline = p
        return p
    }

    private func tapView(_ tex: VKTexture, _ t: DepthTapState) -> UInt32? {
        let id = ObjectIdentifier(tex.image)
        if let v = t.views[id], v.image === tex.image { return v.slot }
        for (k, v) in t.views where v.image == nil {
            let view = v.view, slot = v.slot
            t.views[k] = nil
            deferDestroy { [ctx, fn] in
                if let view { fn.vkDestroyImageView!(ctx.pointee.device, view, nil) }
                _ = slot
            }
            textureIndices.release(slot, count: 1)
        }
        guard tex.image.usage & VK_IMAGE_USAGE_SAMPLED_BIT.rawValue != 0, let slot = textureIndices.allocate(1) else { return nil }
        var err = [CChar](repeating: 0, count: 256)
        let identity = VkComponentMapping(r: VK_COMPONENT_SWIZZLE_IDENTITY, g: VK_COMPONENT_SWIZZLE_IDENTITY,
                                          b: VK_COMPONENT_SWIZZLE_IDENTITY, a: VK_COMPONENT_SWIZZLE_IDENTITY)
        var vi = yvk_view_info(image: tex.image.vkImage, viewType: VK_IMAGE_VIEW_TYPE_2D, format: tex.image.format.format,
                               aspect: (tex.format.isDepth ? VK_IMAGE_ASPECT_DEPTH_BIT : VK_IMAGE_ASPECT_COLOR_BIT).rawValue, baseLevel: 0, levelCount: 1, baseLayer: 0, layerCount: 1,
                               components: identity, usage: VK_IMAGE_USAGE_SAMPLED_BIT.rawValue)
        guard let view = yvk_view_create(ctx, &vi, &err, err.count) else {
            textureIndices.release(slot, count: 1)
            log("depth tap: view: \(cString(err))")
            return nil
        }
        yvk_heap_write_sampled(ctx, slot, view)
        t.views[id] = DepthTapState.View(image: tex.image, view: view, slot: slot)
        return slot
    }

    private func tapSlot(_ t: DepthTapState, bytes: Int) -> Int? {
        let i = t.next
        t.next = (t.next + 1) % t.slots.count
        if t.slots[i].bytes < bytes {
            if t.slots[i].buffer.buffer != nil { var b = t.slots[i].buffer; deferDestroy { [ctx] in yvk_buffer_destroy(ctx, &b) } }
            var b = yvk_buffer()
            var err = [CChar](repeating: 0, count: 256)
            guard yvk_buffer_create(ctx, VkDeviceSize(bytes + 8), YVK_MEMORY_HOST, nil, &b, &err, err.count) == 0 else {
                log("depth tap: buffer: \(cString(err))")
                return nil
            }
            t.slots[i].buffer = b
            t.slots[i].bytes = bytes
        }
        t.slots[i].buffer.mapped.map { ($0 + t.slots[i].bytes).storeBytes(of: UInt64(0), as: UInt64.self) }
        t.slots[i].published = false
        return i
    }

    func collectFinishedCaptures(_ t: DepthTapState) {
        for i in t.slots.indices where !t.slots[i].published && t.slots[i].serial != 0 {
            guard let base = t.slots[i].buffer.mapped else { continue }
            let s = t.slots[i]
            let tail = base + s.bytes
            guard tail.load(as: UInt64.self) == s.serial else { continue }
            let words = (s.width + 1) / 2
            var samples = [UInt16](repeating: 0, count: s.width * s.height)
            samples.withUnsafeMutableBufferPointer { out in
                for y in 0..<s.height {
                    let row = base.advanced(by: y * words * 4).assumingMemoryBound(to: UInt16.self)
                    for x in 0..<s.width { out[y * s.width + x] = row[x] }
                }
            }
            guard tail.load(as: UInt64.self) == s.serial else { continue }
            t.slots[i].published = true
            XRDepthTap.shared.publish(XRDepthCapture(serial: s.serial, width: s.width, height: s.height, samples: samples,
                                                     roomPasses: s.roomPasses, windowsPasses: s.windowsPasses, recordedAt: s.recordedAt))
        }
        environmentCollect(t)
    }

    private func depthTapProvenance(_ mcb: MetalCommandBuffer, serial own: UInt64?, _ t: DepthTapState) {
        var reads = Set<ObjectIdentifier>(), writes: [VKImage] = []
        func read(_ h: MetalHandle?) { if let h, let x = textures[h] { reads.insert(ObjectIdentifier(x.image)) } }
        func write(_ h: MetalHandle?) { if let h, let x = textures[h] { writes.append(x.image) } }
        for pass in mcb.passes {
            switch pass {
            case .render(let p):
                if let d = p.descriptor {
                    for c in d.colorAttachments {
                        if c.attachment.loadAction == MetalLoadAction.load { read(c.attachment.texture) }
                        write(c.attachment.texture)
                        write(c.attachment.resolveTexture)
                    }
                }
                for c in p.commands { if case .setTexture(_, _, let x) = c { read(x) } }
            case .compute(let cmds):
                for c in cmds { if case .setTexture(_, let x) = c { read(x); if let x, (textures[x]?.metalUsage ?? 0) & MetalTextureUsage.shaderWrite != 0 { write(x) } } }
            case .blit(let cmds):
                for c in cmds {
                    switch c {
                    case .copyTextureToTexture(let s, _, _, _, _, let d, _, _, _): read(s); write(d)
                    case .copyTextureSlices(let s, _, _, let d, _, _, _, _): read(s); write(d)
                    default: break
                    }
                }
            default: break
            }
        }
        let serial = own ?? reads.compactMap { t.imageSerials[$0] }.max()
        guard let serial else { return }
        var surfaces: [UInt32] = []
        for image in writes {
            t.imageSerials[ObjectIdentifier(image)] = serial
            if let s = image.surface { surfaces.append(s.surfaceID) }
        }
        if t.imageSerials.count > 4096 { t.imageSerials.removeAll() }
        if !surfaces.isEmpty {
            let tap = XRDepthTap.shared
            tap.recordSurfaces(surfaces, serial: serial)
        }
    }

    func depthTapNoteTexture(_ tex: VKTexture) {
        guard tex.textureType == MetalTextureType.typeCube, tex.metalFormat == 115, tex.image.width == 256, tex.image.levels == 9,
              tex.metalUsage == MetalTextureUsage.shaderRead else { return }
        tap.cube = tex
        if XRDepthTap.log { log("depth tap: environment cube candidate 256² × 9 levels") }
    }

    private func environmentCopy(_ rec: Recording, _ t: DepthTapState) {
        let now = DispatchTime.now().uptimeNanoseconds
        guard !t.cubeCopyPending, now >= t.nextCubeCopy, let cube = t.cube else { return }
        t.nextCubeCopy = now + 2_000_000_000
        let level = t.cubeLevel, size = max(1, cube.image.width >> level)
        let bytes = size * size * 8 * 6
        if t.cubeBytes < bytes {
            if t.cubeBuffer.buffer != nil { var b = t.cubeBuffer; deferDestroy { [ctx] in yvk_buffer_destroy(ctx, &b) } }
            var err = [CChar](repeating: 0, count: 256)
            guard yvk_buffer_create(ctx, VkDeviceSize(bytes + 8), YVK_MEMORY_HOST, nil, &t.cubeBuffer, &err, err.count) == 0 else { return }
            t.cubeBytes = bytes
        }
        t.cubeSerial += 1
        t.cubeBuffer.mapped.map { ($0 + bytes).storeBytes(of: UInt64(0), as: UInt64.self) }
        barrier(rec.cb)
        var region = VkBufferImageCopy()
        region.imageSubresource = VkImageSubresourceLayers(aspectMask: VK_IMAGE_ASPECT_COLOR_BIT.rawValue, mipLevel: UInt32(level),
                                                           baseArrayLayer: 0, layerCount: 6)
        region.imageExtent = VkExtent3D(width: UInt32(size), height: UInt32(size), depth: 1)
        fn.vkCmdCopyImageToBuffer!(rec.cb, cube.image.vkImage, VK_IMAGE_LAYOUT_GENERAL, t.cubeBuffer.buffer, 1, &region)
        barrier(rec.cb)
        var s = t.cubeSerial
        fn.vkCmdUpdateBuffer!(rec.cb, t.cubeBuffer.buffer, VkDeviceSize(bytes), 8, &s)
        yvk_cmd_memory_barrier(rec.cb, allCommands, memoryWrite, VK_PIPELINE_STAGE_2_HOST_BIT, VK_ACCESS_2_HOST_READ_BIT)
        t.cubeCopyPending = true
    }

    private func environmentCollect(_ t: DepthTapState) {
        guard t.cubeCopyPending, let base = t.cubeBuffer.mapped, let cube = t.cube else { return }
        let size = max(1, cube.image.width >> t.cubeLevel), bytes = size * size * 8 * 6
        guard (base + bytes).load(as: UInt64.self) == t.cubeSerial else { return }
        t.cubeCopyPending = false
        let data = [UInt8](UnsafeRawBufferPointer(start: base, count: bytes))
        var h: UInt64 = 0xcbf29ce484222325
        var i = 0
        while i < data.count { h = (h ^ UInt64(data[i])) &* 0x100000001b3; i += 61 }
        guard h != t.envHash, data.contains(where: { $0 != 0 }) else { return }
        t.envHash = h
        t.envSerial += 1
        XRDepthTap.shared.publishEnvironment(XREnvironmentCapture(serial: t.envSerial, size: size, level: t.cubeLevel, halfFloats: data, hash: h))
        if XRDepthTap.log { log("depth tap: environment \(size)² level \(t.cubeLevel) changed (serial \(t.envSerial))") }
    }
}

extension XRDepthTap {
    fileprivate func recordSurfaces(_ ids: [UInt32], serial: UInt64) {
        lock.withLock {
            for id in ids { surfaceSerials[id] = serial }
            if surfaceSerials.count > 64 { surfaceSerials.removeAll() }
        }
    }

    fileprivate func publishEnvironment(_ e: XREnvironmentCapture) { lock.withLock { environment = e } }
}
