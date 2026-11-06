import Foundation

extension Result {
    public var error: Failure? {
        switch self {
        case .success: return nil
        case .failure(let error): return error
        }
    }

    public var value: Success? {
        switch self {
        case .success(let value): return value
        case .failure: return nil
        }
    }
}
