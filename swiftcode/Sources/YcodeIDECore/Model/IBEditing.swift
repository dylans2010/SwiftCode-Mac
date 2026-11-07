#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

extension IBDocument {
    public static func number(_ v: CGFloat) -> String {
        let r = (v * 100).rounded() / 100
        if r == 0 { return "0.0" }
        if r == r.rounded() { return String(Int(r)) }
        var s = String(format: "%.2f", Double(r))
        while s.hasSuffix("0") { s.removeLast() }
        return s
    }

    public func makeObjectID<G: RandomNumberGenerator>(using g: inout G) -> String {
        let chars = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        while true {
            func part(_ n: Int) -> String { String((0..<n).map { _ in chars[Int.random(in: 0..<chars.count, using: &g)] }) }
            let id = "\(part(3))-\(part(2))-\(part(3))"
            if byID[id] == nil && !String(decoding: source, as: UTF8.self).contains("\"\(id)\"") { return id }
        }
    }

    public func makeObjectID() -> String {
        var g = SystemRandomNumberGenerator()
        return makeObjectID(using: &g)
    }

    func edited(_ edits: [XMLEdit?]) throws -> IBDocument {
        let list = edits.compactMap { $0 }
        return list.isEmpty ? self : try IBDocument(data: Data(XMLEdit.apply(list, to: source)))
    }

    public func settingFrame(_ f: CGRect, of id: String) throws -> IBDocument {
        guard let n = byID[id]?.frameNode else { return self }
        return try edited([("x", f.minX), ("y", f.minY), ("width", f.width), ("height", f.height)].map {
            XMLEdit.setAttribute($0.0, Self.number($0.1), on: n, in: source)
        })
    }

    public func storedFrame(forRootFrame r: CGRect, of id: String) -> CGRect? {
        guard let o = byID[id], let p = o.parent, p.isView, let pr = frameInRoot(p), let pf = p.frame else {
            return byID[id].map { CGRect(origin: $0.frame?.origin ?? .zero, size: r.size) }
        }
        let localTop = r.minY - pr.minY
        let y = isFlippedRuntime ? localTop : pf.height - localTop - r.height
        return CGRect(x: r.minX - pr.minX, y: y, width: r.width, height: r.height)
    }

    func cell(of o: Object) -> Object? { o.children.first { $0.key == "cell" } }

    public func title(of id: String) -> String? {
        guard let o = byID[id] else { return nil }
        if let t = o.attribute("title") ?? o.attribute("text") { return t }
        if let c = cell(of: o), let t = c.attribute("title") { return t }
        return o.node.child("state", key: "normal")?["title"]
    }

    public func settingTitle(_ value: String, of id: String) throws -> IBDocument {
        guard let o = byID[id] else { return self }
        if o.attribute("text") != nil || o.element == "label" { return try edited([XMLEdit.setAttribute("text", value, on: o.node, in: source)]) }
        if o.attribute("title") != nil { return try edited([XMLEdit.setAttribute("title", value, on: o.node, in: source)]) }
        if let c = cell(of: o) { return try edited([XMLEdit.setAttribute("title", value, on: c.node, in: source)]) }
        if let state = o.node.child("state", key: "normal") {
            let config = o.node.child("buttonConfiguration", key: "configuration")
            return try edited([XMLEdit.setAttribute("title", value, on: state, in: source), config.flatMap { XMLEdit.setAttribute("title", value, on: $0, in: source) }])
        }
        return try edited([XMLEdit.setAttribute("title", value, on: o.node, in: source)])
    }

    public func placeholder(of id: String) -> String? {
        guard let o = byID[id] else { return nil }
        return o.attribute("placeholder") ?? cell(of: o)?.attribute("placeholderString")
    }

    public func settingPlaceholder(_ value: String?, of id: String) throws -> IBDocument {
        guard let o = byID[id] else { return self }
        let v = value?.isEmpty == true ? nil : value
        if let c = cell(of: o) { return try edited([XMLEdit.setAttribute("placeholderString", v, on: c.node, in: source)]) }
        return try edited([XMLEdit.setAttribute("placeholder", v, on: o.node, in: source)])
    }

    public func isHidden(_ id: String) -> Bool { byID[id]?.attribute("hidden") == "YES" }

    public func settingHidden(_ hidden: Bool, of id: String) throws -> IBDocument {
        guard let o = byID[id] else { return self }
        return try edited([XMLEdit.setAttribute("hidden", hidden ? "YES" : nil, on: o.node, in: source)])
    }

    public func isEnabled(_ id: String) -> Bool {
        guard let o = byID[id] else { return true }
        return (cell(of: o)?.attribute("enabled") ?? o.attribute("enabled")) != "NO"
    }

    public func settingEnabled(_ enabled: Bool, of id: String) throws -> IBDocument {
        guard let o = byID[id] else { return self }
        return try edited([XMLEdit.setAttribute("enabled", enabled ? nil : "NO", on: (cell(of: o) ?? o).node, in: source)])
    }

    public func alignment(of id: String) -> String? {
        guard let o = byID[id] else { return nil }
        return cell(of: o)?.attribute("alignment") ?? o.attribute("textAlignment")
    }

    public func settingAlignment(_ value: String, of id: String) throws -> IBDocument {
        guard let o = byID[id] else { return self }
        if let c = cell(of: o) { return try edited([XMLEdit.setAttribute("alignment", value, on: c.node, in: source)]) }
        return try edited([XMLEdit.setAttribute("textAlignment", value, on: o.node, in: source)])
    }
}
