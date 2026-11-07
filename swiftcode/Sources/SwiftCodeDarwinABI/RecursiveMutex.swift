#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum DebugLockNames {
    nonisolated(unsafe) public static var register: ((UnsafeMutableRawPointer, String) -> Void)?
}

public final class RecursiveMutex: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    public init() {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        var attr = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        pthread_mutexattr_settype(&attr, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attr)
        pthread_mutexattr_destroy(&attr)
    }

    public convenience init(name: String) {
        self.init()
        DebugLockNames.register?(UnsafeMutableRawPointer(mutex), name)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    public func lock() { pthread_mutex_lock(mutex) }
    public func unlock() { pthread_mutex_unlock(mutex) }

    @inline(__always)
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}
