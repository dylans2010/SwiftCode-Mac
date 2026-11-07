import Testing

actor HeavyIntegrationLock {
    static let shared = HeavyIntegrationLock()
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !held { held = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { held = false } else { waiters.removeFirst().resume() }
    }
}

struct HeavyIntegrationTrait: SuiteTrait, TestScoping {
    var isRecursive: Bool { false }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        ProcessAudit.arm()
        await HeavyIntegrationLock.shared.acquire()
        do { try await function() } catch {
            ProcessAudit.checkAfterSuite(test.name)
            await HeavyIntegrationLock.shared.release()
            throw error
        }
        ProcessAudit.checkAfterSuite(test.name)
        await HeavyIntegrationLock.shared.release()
    }
}

extension Trait where Self == HeavyIntegrationTrait {
    static var heavyIntegration: Self { Self() }
}
