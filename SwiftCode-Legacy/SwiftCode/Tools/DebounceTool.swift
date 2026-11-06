import Foundation

public actor DebounceTool {
    private var task: Task<Void, Never>?

    public func debounce(delay: TimeInterval, action: @escaping @Sendable () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled {
                await action()
            }
        }
    }
}
