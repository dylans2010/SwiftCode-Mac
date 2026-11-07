import Foundation
import Testing
@testable import SwiftCodeDebug

@Suite(.serialized) struct InterprocessLockTests {
    final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        private var inside = 0
        private(set) var overlapped = false
        func enter() { lock.lock(); n += 1; inside += 1; if inside > 1 { overlapped = true }; lock.unlock() }
        func leave() { lock.lock(); inside -= 1; lock.unlock() }
        var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    @MainActor @Test func waitersLeaveThePoolFree() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-ipl-\(UUID().uuidString).lock").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let held = InterprocessLock(path: path)
        let waiters = ProcessInfo.processInfo.activeProcessorCount * 2
        let counter = Counter()
        let all = Task.detached {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<waiters {
                    group.addTask {
                        let l = await InterprocessLock.acquire(path: path, poll: 0.01)
                        counter.enter()
                        counter.leave()
                        l.unlock()
                    }
                }
            }
        }
        try await Task.sleep(nanoseconds: 300_000_000)
        let ran = Flag()
        Task.detached { ran.set() }
        let end = Date().addingTimeInterval(5)
        while !ran.isSet, Date() < end { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(ran.isSet)
        #expect(counter.count == 0)
        held.unlock()
        let done = Date().addingTimeInterval(30)
        while counter.count < waiters, Date() < done { try await Task.sleep(nanoseconds: 10_000_000) }
        #expect(counter.count == waiters && !counter.overlapped)
        if counter.count == waiters { await all.value }
    }
}
