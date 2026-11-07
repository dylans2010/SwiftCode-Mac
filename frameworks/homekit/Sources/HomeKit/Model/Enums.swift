import Foundation

public struct HMHomeManagerAuthorizationStatus: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let determined = HMHomeManagerAuthorizationStatus(rawValue: 1)
    public static let restricted = HMHomeManagerAuthorizationStatus(rawValue: 2)
    public static let authorized = HMHomeManagerAuthorizationStatus(rawValue: 4)
}

public enum HMHomeHubState: Int, Sendable, Codable {
    case notAvailable = 0
    case connected = 1
    case disconnected = 2
}

public enum HMEventTriggerActivationState: Int, Sendable, Codable {
    case disabled = 0
    case disabledNoHomeHub = 1
    case disabledNoCompatibleHomeHub = 2
    case disabledNoLocationServicesAuthorization = 3
    case enabled = 4
}

public enum HMPresenceEventType: Int, Sendable, Codable {
    case everyEntry = 1
    case everyExit = 2
    case firstEntry = 3
    case lastExit = 4
    public static var atHome: HMPresenceEventType { .firstEntry }
    public static var notAtHome: HMPresenceEventType { .lastExit }
}

public enum HMPresenceEventUserType: Int, Sendable, Codable {
    case currentUser = 1
    case homeUsers = 2
    case customUsers = 3
}

@inline(__always)
func onMain(_ body: @escaping () -> Void) {
    DispatchQueue.main.async(execute: body)
}

final class SwiftCodeConnection: @unchecked Sendable {
    let store: SwiftCodeHomeStore
    var sessionID = UUID()
    weak var manager: HMHomeManager?

    init(store: SwiftCodeHomeStore) { self.store = store }

    func request(_ r: SwiftCodeHomeRequest, _ done: @escaping (Result<SwiftCodeHomeResponse, Error>) -> Void) {
        store.perform(r, session: sessionID) { result in
            onMain {
                switch result {
                case .success(let v): done(.success(v))
                case .failure(let e): done(.failure(e.publicError))
                }
            }
        }
    }

    func simple(_ r: SwiftCodeHomeRequest, _ completion: @escaping (Error?) -> Void) {
        request(r) { result in
            if case .failure(let e) = result { completion(e) } else { completion(nil) }
        }
    }
}

func fail(_ completion: @escaping (Error?) -> Void, _ code: HMError.Code) {
    onMain { completion(HMError(code)) }
}

func asyncCall(_ body: (@escaping (Error?) -> Void) -> Void) async throws {
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
        body { error in
            if let error { c.resume(throwing: error) } else { c.resume() }
        }
    }
}

func asyncCall<T>(_ body: (@escaping (T?, Error?) -> Void) -> Void) async throws -> T {
    try await withCheckedThrowingContinuation { (c: CheckedContinuation<T, Error>) in
        body { value, error in
            if let error { c.resume(throwing: error) } else if let value { c.resume(returning: value) } else {
                c.resume(throwing: HMError(.unexpectedError))
            }
        }
    }
}
