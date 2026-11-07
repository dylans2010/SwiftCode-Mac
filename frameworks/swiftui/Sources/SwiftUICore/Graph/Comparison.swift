import Foundation

package protocol GraphInputComparable {
    func _isGraphInputEqual(to other: Any) -> Bool
}

package enum GraphComparison {
    static let maxDepth = 12

    package static func fieldsEqual(_ a: Any, _ b: Any) -> Bool {
        guard ObjectIdentifier(type(of: a)) == ObjectIdentifier(type(of: b)) else { return false }
        if let g = a as? any GraphInputComparable { return g._isGraphInputEqual(to: b) }
        let ma = Mirror(reflecting: a), mb = Mirror(reflecting: b)
        if ma.displayStyle == .class { return identical(a, b) }
        return childrenEqual(ma, mb, depth: 0)
    }

    package static func valuesEqual(_ a: Any, _ b: Any) -> Bool { valuesEqual(a, b, depth: 0) }

    private static func valuesEqual(_ a: Any, _ b: Any, depth: Int) -> Bool {
        guard depth <= maxDepth else { return false }
        guard ObjectIdentifier(type(of: a)) == ObjectIdentifier(type(of: b)) else { return false }
        if let g = a as? any GraphInputComparable { return g._isGraphInputEqual(to: b) }
        let ma = Mirror(reflecting: a)
        if ma.displayStyle == .class { return identical(a, b) }
        if isFunction(a, ma) { return false }
        if let e = a as? any Equatable { return equatableEqual(e, b) }
        let mb = Mirror(reflecting: b)
        switch ma.displayStyle {
        case .optional?:
            let ca = Array(ma.children), cb = Array(mb.children)
            if ca.isEmpty || cb.isEmpty { return ca.isEmpty && cb.isEmpty }
            return valuesEqual(ca[0].value, cb[0].value, depth: depth + 1)
        case .struct?, .tuple?, .collection?:
            return childrenEqual(ma, mb, depth: depth)
        case .enum?:
            let ca = Array(ma.children), cb = Array(mb.children)
            if ca.isEmpty && cb.isEmpty { return String(describing: a) == String(describing: b) }
            return childrenEqual(ma, mb, depth: depth)
        default:
            return false
        }
    }

    private static func childrenEqual(_ ma: Mirror, _ mb: Mirror, depth: Int) -> Bool {
        let ca = Array(ma.children), cb = Array(mb.children)
        guard ca.count == cb.count else { return false }
        for (x, y) in zip(ca, cb) {
            guard x.label == y.label, valuesEqual(x.value, y.value, depth: depth + 1) else { return false }
        }
        return true
    }

    private static func identical(_ a: Any, _ b: Any) -> Bool {
        (a as AnyObject) === (b as AnyObject)
    }

    private static func isFunction(_ a: Any, _ m: Mirror) -> Bool {
        m.displayStyle == nil && m.children.isEmpty && String(describing: type(of: a)).contains("->")
    }

    private static func equatableEqual<T: Equatable>(_ a: T, _ b: Any) -> Bool {
        guard let b = b as? T else { return false }
        return a == b
    }
}
