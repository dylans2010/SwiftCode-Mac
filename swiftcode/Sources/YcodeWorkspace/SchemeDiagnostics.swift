import Foundation

public struct SchemeDiagnostics: Equatable, Sendable {
    public var addressSanitizer = false
    public var stackUseAfterReturn = false
    public var threadSanitizer = false
    public var undefinedBehaviorSanitizer = false

    public init(addressSanitizer: Bool = false, stackUseAfterReturn: Bool = false, threadSanitizer: Bool = false,
                undefinedBehaviorSanitizer: Bool = false) {
        self.addressSanitizer = addressSanitizer
        self.stackUseAfterReturn = stackUseAfterReturn
        self.threadSanitizer = threadSanitizer
        self.undefinedBehaviorSanitizer = undefinedBehaviorSanitizer
    }

    public static var attributes: [(key: WritableKeyPath<SchemeDiagnostics, Bool>, name: String)] {
        [
            (\.addressSanitizer, "enableAddressSanitizer"),
            (\.stackUseAfterReturn, "enableASanStackUseAfterReturn"),
            (\.threadSanitizer, "enableThreadSanitizer"),
            (\.undefinedBehaviorSanitizer, "enableUBSanitizer"),
        ]
    }

    public var isEmpty: Bool { self == SchemeDiagnostics() }

    public mutating func set(_ key: WritableKeyPath<SchemeDiagnostics, Bool>, _ on: Bool) {
        self[keyPath: key] = on
        if on, key == \.addressSanitizer { threadSanitizer = false }
        if on, key == \.threadSanitizer { addressSanitizer = false; stackUseAfterReturn = false }
        if !addressSanitizer { stackUseAfterReturn = false }
    }
}

extension Scheme {
    public func diagnostics(for action: String = "LaunchAction") -> SchemeDiagnostics {
        var d = SchemeDiagnostics()
        guard let node = document.child(action) else { return d }
        for a in SchemeDiagnostics.attributes { d[keyPath: a.key] = node[a.name] == "YES" }
        if !d.addressSanitizer { d.stackUseAfterReturn = false }
        return d
    }

    public mutating func setDiagnostics(_ d: SchemeDiagnostics, for action: String = "LaunchAction") {
        editAction(action) { node in
            for a in SchemeDiagnostics.attributes { node[a.name] = d[keyPath: a.key] ? "YES" : nil }
        }
    }
}
