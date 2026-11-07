#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum LeafLockCheck {
    nonisolated(unsafe) public static var enabled = getenv("SWIFTCODE_LOCK_ORDER_CHECK").map { String(cString: $0) == "1" } ?? false

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    public static var depth: Int {
        guard enabled else { return 0 }
        return Int(bitPattern: pthread_getspecific(key))
    }

    @inline(__always) static func entered() {
        guard enabled else { return }
        pthread_setspecific(key, UnsafeRawPointer(bitPattern: Int(bitPattern: pthread_getspecific(key)) + 1))
    }

    @inline(__always) static func left() {
        guard enabled else { return }
        pthread_setspecific(key, UnsafeRawPointer(bitPattern: Int(bitPattern: pthread_getspecific(key)) - 1))
    }
}

public final class DescriptorTableLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    public init(name: String = "descriptor table") {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        var attr = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        pthread_mutexattr_settype(&attr, Int32(PTHREAD_MUTEX_RECURSIVE))
        pthread_mutex_init(mutex, &attr)
        pthread_mutexattr_destroy(&attr)
        DebugLockNames.register?(UnsafeMutableRawPointer(mutex), name)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    @inline(__always)
    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        LeafLockCheck.entered()
        defer {
            LeafLockCheck.left()
            pthread_mutex_unlock(mutex)
        }
        return try body()
    }
}
