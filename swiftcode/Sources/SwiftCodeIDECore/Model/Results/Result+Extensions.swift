// Adapted from SwiftCode-Legacy SwiftCode/Core/Common/Result+Extensions.swift (Dylan's own code;
// direct port authorised under MIT). See bulk/core-dispositions.tsv.
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
