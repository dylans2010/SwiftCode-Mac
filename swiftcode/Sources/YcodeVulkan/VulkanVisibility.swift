import CVulkan
import Foundation
import YcodeMetalHost

struct VisibilityQueries {
    let pool: VkQueryPool
    let first: UInt32
    let capacity: UInt32
    let buffer: VKBuffer
    let bufferHandle: MetalHandle
    let precise: Bool
    var mode: UInt64 = 0
    var offset = 0
    var used: UInt32 = 0
    var active = false
    var segments: [(query: UInt32, offset: Int)] = []
    var label = ""
    var segmentDraws: [Int] = []
}

struct VisibilityRead {
    let pool: VkQueryPool
    let query: UInt32
    let key: String
}

extension VulkanMetalBackend {
    static let visibilityPoolSize = 1024

    nonisolated(unsafe) static var visibilityLogged = 0

    func visibilityQueries(_ pass: MetalRenderPass, _ rec: Recording, width: Int = 0, height: Int = 0) -> VisibilityQueries? {
        guard let d = pass.descriptor, pass.commands.contains(where: {
            if case .setVisibilityResultMode(let m, _) = $0 { return m != 0 }
            return false
        }) else { return nil }
        guard let vh = d.visibilityResultBuffer, let vb = buffers[vh] else {
            noteVisibility("visibility: a pass sets a visibility mode without a visibility result buffer; not counted")
            return nil
        }
        let count = pass.commands.count
        guard count <= Self.visibilityPoolSize else {
            noteVisibility("visibility: a pass of \(count) commands is beyond the query pool (\(Self.visibilityPoolSize)); not counted")
            return nil
        }
        if rec.visibilityPool == nil || rec.visibilityUsed + count > Self.visibilityPoolSize {
            guard let p = freeVisibilityPools.popLast() ?? makeVisibilityPool() else { return nil }
            rec.visibilityPool = p
            rec.visibilityPools.append(p)
            rec.visibilityUsed = 0
        }
        guard let pool = rec.visibilityPool else { return nil }
        let first = UInt32(rec.visibilityUsed)
        rec.visibilityUsed += count
        fn.vkCmdResetQueryPool!(rec.cb, pool, first, UInt32(count))
        statistics.visibilityPasses += 1
        var v = VisibilityQueries(pool: pool, first: first, capacity: UInt32(count), buffer: vb, bufferHandle: vh,
                                  precise: ctx.pointee.features.occlusionQueryPrecise != 0)
        if Self.debugVisibilityStats { v.label = visibilityLabel(pass, d, width: width, height: height, buffer: vh) }
        return v
    }

    func makeVisibilityPool() -> VkQueryPool? {
        var ci = VkQueryPoolCreateInfo(sType: VK_STRUCTURE_TYPE_QUERY_POOL_CREATE_INFO, pNext: nil, flags: 0,
                                       queryType: VK_QUERY_TYPE_OCCLUSION, queryCount: UInt32(Self.visibilityPoolSize),
                                       pipelineStatistics: 0)
        var p: VkQueryPool?
        guard fn.vkCreateQueryPool!(device, &ci, nil, &p) == VK_SUCCESS, let p else {
            noteVisibility("visibility: vkCreateQueryPool failed; not counted")
            return nil
        }
        return p
    }

    func retireVisibilityPools(_ rec: Recording, serial: UInt64) {
        guard !rec.visibilityPools.isEmpty else { return }
        let pools = rec.visibilityPools
        let reads = rec.visibilityReads
        rec.visibilityPools.removeAll()
        rec.visibilityReads.removeAll()
        rec.visibilityPool = nil
        graveyard.append((serial, { [unowned self] in
            if !reads.isEmpty { self.countVisibilityResults(reads) }
            self.freeVisibilityPools.append(contentsOf: pools)
        }))
    }

    func setVisibilityMode(_ v: inout VisibilityQueries, _ mode: UInt64, offset: Int, _ cb: VkCommandBuffer?) {
        endVisibilityQuery(&v, cb)
        v.mode = mode
        v.offset = offset
        if mode != 0 && Self.visibilityLogged < 12 {
            noteVisibility("visibility: mode \(mode) at offset \(offset) of #\(v.bufferHandle.raw) (\(v.buffer.length) B)")
        }
    }

    func beginVisibilityQuery(_ v: inout VisibilityQueries, _ cb: VkCommandBuffer?) {
        if v.active, !v.segmentDraws.isEmpty { v.segmentDraws[v.segmentDraws.count - 1] += 1 }
        guard v.mode != 0, !v.active, v.used < v.capacity else { return }
        let q = v.first + v.used
        v.used += 1
        let flags = v.mode == 2 && v.precise ? VK_QUERY_CONTROL_PRECISE_BIT.rawValue : 0
        fn.vkCmdBeginQuery!(cb, v.pool, q, flags)
        v.active = true
        v.segments.append((q, v.offset))
        v.segmentDraws.append(1)
    }

    func endVisibilityQuery(_ v: inout VisibilityQueries, _ cb: VkCommandBuffer?) {
        guard v.active else { return }
        fn.vkCmdEndQuery!(cb, v.pool, v.first + v.used - 1)
        v.active = false
    }

    func writeVisibilityResults(_ v: VisibilityQueries, _ cb: VkCommandBuffer?, _ rec: Recording? = nil) {
        guard !v.segments.isEmpty else { return }
        var last: [Int: UInt32] = [:]
        var shared = 0
        for s in v.segments {
            if last[s.offset] != nil { shared += 1 }
            last[s.offset] = s.query
        }
        let flags = VK_QUERY_RESULT_64_BIT.rawValue | VK_QUERY_RESULT_WAIT_BIT.rawValue
        for (offset, q) in last {
            guard offset >= 0, offset % 8 == 0, offset + 8 <= v.buffer.length else {
                noteVisibility("visibility: offset \(offset) outside #\(v.bufferHandle.raw) (\(v.buffer.length) B); not written")
                continue
            }
            if let forced = Self.debugForcedVisibility {
                fn.vkCmdFillBuffer!(cb, v.buffer.vkBuffer, VkDeviceSize(v.buffer.offset + offset), 8, forced)
            } else {
                fn.vkCmdCopyQueryPoolResults!(cb, v.pool, q, 1, v.buffer.vkBuffer, VkDeviceSize(v.buffer.offset + offset), 8, flags)
            }
        }
        if Self.debugVisibilityStats, let rec {
            for (i, s) in v.segments.enumerated() {
                rec.visibilityReads.append(VisibilityRead(pool: v.pool, query: s.query,
                                                          key: "\(v.label) slot \(s.offset) segment draws \(v.segmentDraws[i])"))
            }
        }
        statistics.visibilityQueries += v.segments.count
        statistics.visibilitySharedSlots += shared
        if Self.visibilityLogged < 12 || (shared > 0 && Self.visibilityLogged < 24) {
            noteVisibility("visibility: pass with \(v.segments.count) queries into \(last.count) slots of #\(v.bufferHandle.raw)"
                + (shared > 0 ? "; \(shared) segments share a slot (the last one's count is kept)" : ""))
        }
    }

    static let debugForcedVisibility = ProcessInfo.processInfo.environment["SWIFTCODE_DEBUG_VISIBILITY_FORCE"].flatMap(UInt32.init)

    static let debugVisibilityStats = ProcessInfo.processInfo.environment["SWIFTCODE_DEBUG_VISIBILITY_STATS"] == "1"
    nonisolated(unsafe) static var visibilityCounts: [String: (zero: Int, nonzero: Int)] = [:]
    nonisolated(unsafe) static var visibilityCountsLogged = Date()

    func visibilityLabel(_ pass: MetalRenderPass, _ d: MetalRenderPassDescriptor, width: Int, height: Int, buffer: MetalHandle) -> String {
        var states = Set<String>(), kinds = [String: Int]()
        for c in pass.commands {
            switch c {
            case .setDepthStencilState(let h):
                let s = h.flatMap { depthStencilStates[$0] }
                states.insert(s.map { "cmp\($0.depthCompareFunction)\($0.depthWriteEnabled ? "w" : "")\($0.frontFaceStencil == nil ? "" : "s")" } ?? "none")
            case .draw: kinds["draw", default: 0] += 1
            case .drawIndexed: kinds["indexed", default: 0] += 1
            case .drawIndirect: kinds["indirect", default: 0] += 1
            case .drawIndexedIndirect: kinds["indexedIndirect", default: 0] += 1
            default: break
            }
        }
        let depth = d.depth.map { a -> String in
            let fmt = a.texture.flatMap { textures[$0] }.map { "\($0.metalFormat)/\($0.image.samples)x" } ?? "?"
            return " depth \(fmt) load \(a.loadAction) store \(a.storeAction) clear \(d.clearDepth)"
        } ?? ""
        return "\(width)x\(height) \(d.colorAttachments.count)c\(depth) states [\(states.sorted().joined(separator: ","))] "
            + "draws \(kinds.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ",")) #\(buffer.raw)"
    }

    func countVisibilityResults(_ reads: [VisibilityRead]) {
        for r in reads {
            var value: UInt64 = 0
            let res = fn.vkGetQueryPoolResults!(device, r.pool, r.query, 1, 8, &value, 8, VK_QUERY_RESULT_64_BIT.rawValue)
            guard res == VK_SUCCESS else { continue }
            var c = Self.visibilityCounts[r.key] ?? (0, 0)
            if value == 0 { c.zero += 1 } else { c.nonzero += 1 }
            Self.visibilityCounts[r.key] = c
        }
        guard Date().timeIntervalSince(Self.visibilityCountsLogged) >= 20 else { return }
        Self.visibilityCountsLogged = Date()
        let lines = Self.visibilityCounts.sorted { $0.key < $1.key }.prefix(40)
            .map { "\($0.key): \($0.value.zero) zero, \($0.value.nonzero) not" }
        log("visibility statistics: " + lines.joined(separator: "; "))
    }

    func noteVisibility(_ message: String) {
        guard Self.visibilityLogged < 24 else { return }
        Self.visibilityLogged += 1
        log(message)
    }
}

extension VulkanMetalBackend {
    static let debugPassDrawsSize: (Int, Int)? = {
        guard let v = ProcessInfo.processInfo.environment["SWIFTCODE_DEBUG_PASS_DRAWS"] else { return nil }
        let p = v.split(separator: "x").compactMap { Int($0) }
        return p.count == 2 ? (p[0], p[1]) : nil
    }()
    nonisolated(unsafe) static var debugPassDrawsLast: [String: String] = [:]
    static let debugPassDrawsAllAfter = Double(ProcessInfo.processInfo.environment["SWIFTCODE_DEBUG_PASS_DRAWS_ALL"] ?? "")
    nonisolated(unsafe) static var debugPassDrawsFirst: UInt64 = 0
    static let debugPassDrawsBuffers = ProcessInfo.processInfo.environment["SWIFTCODE_DEBUG_PASS_DRAWS_BUFFERS"] == "1"
    nonisolated(unsafe) static var debugPassDrawsLines = 0

    func debugPassDraws(_ pass: MetalRenderPass, width: Int, height: Int, process: MetalProcessID) {
        guard let want = Self.debugPassDrawsSize, want == (width, height), Self.debugPassDrawsLines < 20000,
              let d = pass.descriptor else { return }
        func short(_ t: TranslatedShader?) -> String { t?.reflection.entryPoint ?? "-" }
        var pipeline: VKRenderPipeline?
        var fragmentTexture: MetalHandle?
        var fragmentBuffers: [Int: MetalHandle] = [:]
        var depthState = "-", cull: UInt64 = 0, winding: UInt64 = 0, clip: UInt64 = 0, stencilRef = ""
        var sig: [String] = [], line: [String] = []
        for c in pass.commands {
            var s: String?, extra = ""
            switch c {
            case .setRenderPipelineState(let h): pipeline = h.flatMap { renderPipelines[$0] }
            case .setTexture(let st, let index, let t) where st == .fragment && index == 0: fragmentTexture = t
            case .setBuffer(let st, let index, let b, _) where st == .fragment: fragmentBuffers[index] = b
            case .setVisibilityResultMode(let m, let off): s = "V\(m)@\(off)"
            case .setDepthStencilState(let h):
                depthState = h.flatMap { depthStencilStates[$0] }.map {
                    "cmp\($0.depthCompareFunction)\($0.depthWriteEnabled ? "w" : "")"
                        + ($0.frontFaceStencil.map { " st\($0)" } ?? "")
                } ?? "none"
            case .setCullMode(let m): cull = m
            case .setFrontFacingWinding(let w): winding = w
            case .setDepthClipMode(let m): clip = m
            case .setStencilReference(let front, let back): stencilRef = " sref\(front)/\(back)"
            case .draw(let dr):
                s = "\(short(pipeline?.vertex))+\(short(pipeline?.fragment)) v\(dr.vertexCount)x\(dr.instanceCount)+\(dr.baseInstance)"
            case .drawIndexed(let dr):
                s = "\(short(pipeline?.vertex))+\(short(pipeline?.fragment)) i\(dr.indexCount)x\(dr.instanceCount)+\(dr.baseInstance)"
                extra = " ib\(dr.indexBuffer?.raw ?? 0) t\(fragmentTexture?.raw ?? 0) [\(depthState) cull\(cull) wind\(winding) clip\(clip)\(stencilRef)"
                    + " pipe \(pipeline.map { "c\($0.desc.colorAttachments.count) d\($0.desc.depthAttachmentPixelFormat) s\($0.desc.stencilAttachmentPixelFormat) n\($0.desc.rasterSampleCount) unknown\($0.desc.unknownKeys.keys.sorted())" } ?? "-")]"
                    + (Self.debugPassDrawsBuffers ? " fb" + fragmentBuffers.sorted { $0.key < $1.key }
                        .map { "\($0.key):\($0.value.raw)" }.joined(separator: ",") : "")
            case .drawIndirect, .drawIndexedIndirect:
                s = "\(short(pipeline?.vertex))+\(short(pipeline?.fragment)) indirect"
            default: break
            }
            if let s { sig.append(s); line.append(s + extra) }
        }
        let loads = (d.colorAttachments.map { "c\($0.index):\($0.attachment.loadAction)/\($0.attachment.storeAction)"
                + (Self.debugPassDrawsAllAfter != nil ? " #\($0.attachment.texture?.raw ?? 0)" : "") }
            + [d.depth.map { "d:\($0.loadAction)/\($0.storeAction) \(d.clearDepth)" }].compactMap { $0 }).joined(separator: " ")
        var visBuf = ""
        if let vh = d.visibilityResultBuffer, let vb = buffers[vh], let p = vb.hostPointer {
            let n = min(vb.length / 8, 4)
            visBuf = " vbuf #\(vh.raw) [" + (0..<n).map { String(p.load(fromByteOffset: 8 * $0, as: UInt64.self)) }.joined(separator: ",") + "]"
        }
        let signature = loads + " | " + sig.joined(separator: "; ")
        let key = "\(process) \(signature.prefix(40))"
        let now = DispatchTime.now().uptimeNanoseconds
        if Self.debugPassDrawsFirst == 0 { Self.debugPassDrawsFirst = now }
        let all = Self.debugPassDrawsAllAfter.map { Double(now - Self.debugPassDrawsFirst) / 1e9 >= $0 } ?? false
        guard all || Self.debugPassDrawsLast[key] != signature || !visBuf.isEmpty else { return }
        Self.debugPassDrawsLast[key] = signature
        Self.debugPassDrawsLines += 1
        log("pass draws \(width)x\(height) t=\(DispatchTime.now().uptimeNanoseconds) process \(process): \(loads)\(visBuf) | "
            + line.joined(separator: "; "))
    }
}
