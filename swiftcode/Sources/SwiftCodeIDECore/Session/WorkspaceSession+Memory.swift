import Foundation
import SwiftCodeDebug

extension WorkspaceSession {
    public var canReadMemory: Bool { debugClient?.capabilities["supportsReadMemoryRequest"]?.bool == true }

    public func readMemory(_ reference: String, offset: Int = 0, count: Int) async -> MemoryBlock? {
        guard let client = debugClient, stoppedThread != nil else { return nil }
        return try? await client.readMemory(memoryReference: reference, offset: offset, count: count)
    }

    public func memoryReference(of expression: String) async -> String? {
        if MemoryBlock.address(expression) != nil { return expression.trimmingCharacters(in: .whitespaces) }
        guard let client = debugClient, stoppedThread != nil,
              let r = try? await client.evaluateFull(expression, frameID: selectedFrameID, context: "watch") else { return nil }
        if let m = r.memoryReference { return m }
        let first = r.result.split(separator: " ").first.map(String.init) ?? r.result
        return MemoryBlock.address(first) != nil ? first : nil
    }
}
