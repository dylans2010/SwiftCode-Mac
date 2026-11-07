import Foundation

public struct MemoryBlock: Equatable, Sendable {
    public var address: UInt64
    public var bytes: [UInt8]
    public var unreadable: Int

    public init(address: UInt64, bytes: [UInt8], unreadable: Int = 0) {
        self.address = address
        self.bytes = bytes
        self.unreadable = unreadable
    }

    public static func address(_ text: String) -> UInt64? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        if t.hasPrefix("0x") { return UInt64(t.dropFirst(2), radix: 16) }
        return UInt64(t)
    }
}

extension DAPClient {
    public func readMemory(memoryReference: String, offset: Int = 0, count: Int) async throws -> MemoryBlock {
        let b = try await request("readMemory", ["memoryReference": .string(memoryReference), "offset": .number(Double(offset)),
                                                 "count": .number(Double(count))])
        let start = MemoryBlock.address(b["address"]?.string ?? memoryReference) ?? 0
        let data = b["data"]?.string.flatMap { Data(base64Encoded: $0) } ?? Data()
        return MemoryBlock(address: start, bytes: [UInt8](data), unreadable: b["unreadableBytes"]?.int ?? max(0, count - data.count))
    }
}
