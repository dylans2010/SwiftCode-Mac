import Foundation

public struct MetalHandle: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
    public static func < (a: MetalHandle, b: MetalHandle) -> Bool { a.raw < b.raw }
    public var description: String { "#\(raw)" }
}

public typealias MetalProcessID = UInt64

public struct GuestSharedRegion: @unchecked Sendable {
    public let pointer: UnsafeMutableRawPointer
    public let length: Int
    public let objectID: UInt64
    public let offset: Int
    public let objectPointer: UnsafeMutableRawPointer
    public let objectLength: Int
    public let owner: AnyObject?

    public init(pointer: UnsafeMutableRawPointer, length: Int, objectID: UInt64, offset: Int = 0,
                objectPointer: UnsafeMutableRawPointer? = nil, objectLength: Int? = nil, owner: AnyObject?) {
        self.pointer = pointer
        self.length = length
        self.objectID = objectID
        self.offset = offset
        self.objectPointer = objectPointer ?? pointer - offset
        self.objectLength = objectLength ?? offset + length
        self.owner = owner
    }

    public func slice(at: Int, count: Int) -> GuestSharedRegion {
        let start = min(max(at, 0), length)
        let n = min(max(count, 0), length - start)
        return GuestSharedRegion(pointer: pointer + start, length: n, objectID: objectID, offset: offset + start,
                                 objectPointer: objectPointer, objectLength: objectLength, owner: owner)
    }

    public func bytes(count: Int? = nil) -> [UInt8] {
        let n = min(count ?? length, length)
        return n <= 0 ? [] : [UInt8](UnsafeRawBufferPointer(start: pointer, count: n))
    }
}

public struct IOSurfaceBacking: @unchecked Sendable {
    public var surfaceID: UInt32
    public var region: GuestSharedRegion
    public var width: Int
    public var height: Int
    public var bytesPerRow: Int
    public var bytesPerElement: Int
    public var pixelFormat: UInt32
    public var plane: Int
    public var planeOffset: Int
    public var syncState: (@Sendable () -> (seed: UInt32, locked: Bool)?)?

    public init(surfaceID: UInt32, region: GuestSharedRegion, width: Int, height: Int, bytesPerRow: Int,
                bytesPerElement: Int, pixelFormat: UInt32, plane: Int = 0, planeOffset: Int = 0) {
        self.surfaceID = surfaceID
        self.region = region
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.bytesPerElement = bytesPerElement
        self.pixelFormat = pixelFormat
        self.plane = plane
        self.planeOffset = planeOffset
    }
}

public struct MetalLimits: Equatable, Sendable {
    public var maxThreadsPerThreadgroup: (x: UInt64, y: UInt64, z: UInt64)
    public var maxThreadgroupMemoryLength: UInt64

    public init(maxThreadsPerThreadgroup: (x: UInt64, y: UInt64, z: UInt64) = (1024, 1024, 1024),
                maxThreadgroupMemoryLength: UInt64 = 32768) {
        self.maxThreadsPerThreadgroup = maxThreadsPerThreadgroup
        self.maxThreadgroupMemoryLength = maxThreadgroupMemoryLength
    }

    public static let macOSHost = MetalLimits()

    public static func == (a: MetalLimits, b: MetalLimits) -> Bool {
        a.maxThreadsPerThreadgroup == b.maxThreadsPerThreadgroup && a.maxThreadgroupMemoryLength == b.maxThreadgroupMemoryLength
    }
}

public struct MetalComputePipelineInfo: Equatable, Sendable {
    public var maxTotalThreadsPerThreadgroup: UInt16
    public var threadExecutionWidth: UInt16
    public init(maxTotalThreadsPerThreadgroup: UInt16 = 1024, threadExecutionWidth: UInt16 = 32) {
        self.maxTotalThreadsPerThreadgroup = maxTotalThreadsPerThreadgroup
        self.threadExecutionWidth = threadExecutionWidth
    }
}

public enum MetalCommandBufferStatus {
    public static let scheduled = 3
    public static let completed = 4
    public static let error = 5
}

public protocol MetalBackend: AnyObject {
    var isAvailable: Bool { get }
    func limits() -> MetalLimits

    func createBuffer(_ handle: MetalHandle, length: Int, storage: MetalStorageMode, guestMemory: GuestSharedRegion?) throws
    func createTexture(_ handle: MetalHandle, _ desc: MetalTextureDescriptor, iosurface: IOSurfaceBacking?) throws
    func createTextureView(_ handle: MetalHandle, parent: MetalHandle, _ desc: MetalTextureViewDescriptor) throws
    func createSampler(_ handle: MetalHandle, _ desc: MetalSamplerDescriptor) throws
    func createDepthStencilState(_ handle: MetalHandle, _ desc: MetalDepthStencilDescriptor) throws
    func createFunction(_ handle: MetalHandle, metallib: [UInt8]) throws
    func createRenderPipeline(_ handle: MetalHandle, _ desc: MetalRenderPipelineDescriptor) throws
    func createComputePipeline(_ handle: MetalHandle, function: MetalHandle) throws -> MetalComputePipelineInfo

    func replaceRegion(texture: MetalHandle, _ region: MetalRegion, level: Int, slice: Int, bytes: [UInt8],
                       bytesPerRow: Int, bytesPerImage: Int) throws
    func getBytes(texture: MetalHandle, _ region: MetalRegion, level: Int, slice: Int, into: GuestSharedRegion,
                  bytesPerRow: Int, bytesPerImage: Int) throws

    func release(_ handle: MetalHandle)

    func submit(_ commandBuffer: MetalCommandBuffer, scheduled: @escaping @Sendable () -> Void,
                completed: @escaping @Sendable (_ status: Int) -> Void)

    func createEvent(_ handle: MetalHandle) throws
    func createEventAlias(_ handle: MetalHandle, of original: MetalHandle) throws
    func createFence(_ handle: MetalHandle) throws
    func signalEvent(_ handle: MetalHandle, value: UInt64)
    func eventValue(_ handle: MetalHandle) -> UInt64?
    func gpuAddress(ofBuffer handle: MetalHandle) -> UInt64?
    func gpuResourceID(ofSampler handle: MetalHandle) -> UInt64?
    func gpuResourceID(ofTexture handle: MetalHandle) -> UInt64?
    func heapSlots(ofTexture handle: MetalHandle) -> (index: UInt32, count: UInt32)?
    func reserveHeapSlots(textures: [MetalHandle: (index: UInt32, count: UInt32)], samplers: [MetalHandle: UInt32])
    func writeBuffer(_ handle: MetalHandle, offset: Int, _ bytes: [UInt8]) -> Bool
    func diagnosticSummary() -> String?
    func snapshotSettle()
    func bufferContents(_ handle: MetalHandle) -> [UInt8]?
    func setBufferContents(_ handle: MetalHandle, _ bytes: [UInt8]) -> Bool
    func shutdown()
    func setDeviceResetHandler(_ handler: @escaping @Sendable () -> Void)
}

public extension MetalBackend {
    func createEvent(_ handle: MetalHandle) throws {}
    func createEventAlias(_ handle: MetalHandle, of original: MetalHandle) throws { try createEvent(handle) }
    func createFence(_ handle: MetalHandle) throws {}
    func signalEvent(_ handle: MetalHandle, value: UInt64) {}
    func eventValue(_ handle: MetalHandle) -> UInt64? { nil }
    func gpuAddress(ofBuffer handle: MetalHandle) -> UInt64? { nil }
    func gpuResourceID(ofSampler handle: MetalHandle) -> UInt64? { nil }
    func gpuResourceID(ofTexture handle: MetalHandle) -> UInt64? { nil }
    func heapSlots(ofTexture handle: MetalHandle) -> (index: UInt32, count: UInt32)? { nil }
    func reserveHeapSlots(textures: [MetalHandle: (index: UInt32, count: UInt32)], samplers: [MetalHandle: UInt32]) {}
    func writeBuffer(_ handle: MetalHandle, offset: Int, _ bytes: [UInt8]) -> Bool { false }
    func diagnosticSummary() -> String? { nil }
    func snapshotSettle() {}
    func bufferContents(_ handle: MetalHandle) -> [UInt8]? { nil }
    func setBufferContents(_ handle: MetalHandle, _ bytes: [UInt8]) -> Bool { false }
    func shutdown() {}
    func setDeviceResetHandler(_ handler: @escaping @Sendable () -> Void) {}
}

public protocol IOSurfaceResolver: AnyObject {
    func backing(forSurfacePort port: UInt32, plane: Int) -> IOSurfaceBacking?
    func makeSharedTextureSurface(allocationSize: Int, name: String, properties: [(key: String, value: UInt64)]) -> UInt32?
    func surfaceDescription(forSurfacePort port: UInt32) -> MetalSurfaceDescription?
}

public extension IOSurfaceResolver {
    func makeSharedTextureSurface(allocationSize: Int, name: String, properties: [(key: String, value: UInt64)]) -> UInt32? { nil }
    func surfaceDescription(forSurfacePort port: UInt32) -> MetalSurfaceDescription? { nil }
}

public struct MetalSurfaceDescription: Equatable, Sendable {
    public var id: UInt32
    public var numbers: [String: UInt64]
    public init(id: UInt32, numbers: [String: UInt64]) {
        self.id = id
        self.numbers = numbers
    }
}

public protocol MetalGuestMemoryResolver: AnyObject {
    func region(forMemoryEntry name: UInt32) -> GuestSharedRegion?
}
