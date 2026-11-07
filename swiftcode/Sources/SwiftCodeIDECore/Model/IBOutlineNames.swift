import Foundation

extension IBDocument {
    public static let entryPointTitle = "Storyboard Entry Point"

    func isSubview(_ o: Object) -> Bool {
        o.isView && o.parent?.isView == true && o.key != "cell"
    }

    func content(of o: Object) -> String? {
        for a in ["title", "text", "placeholder"] { if let t = o.attribute(a), !t.isEmpty { return t } }
        if let t = o.children.first(where: { $0.key == "cell" })?.attribute("title"), !t.isEmpty { return t }
        if let t = o.node.children.first(where: { $0.name == "state" })?["title"], !t.isEmpty { return t }
        return nil
    }

    public func outlineTitle(_ o: Object) -> String {
        if let l = o.attribute("userLabel") { return l }
        if o.element == "viewLayoutGuide", o.key == "safeArea" { return "Safe Area" }
        if o.element == "placeholder", o.attribute("placeholderIdentifier") == "IBFirstResponder" { return "First Responder" }
        if o.element == "exit" { return "Exit" }
        if isSubview(o) { return content(of: o) ?? o.attribute("customClass") ?? kindName(o) }
        if ["navigationItem", "barButtonItem", "tabBarItem", "command", "menu"].contains(o.element) {
            if let t = o.attribute("title"), !t.isEmpty { return t }
            if let s = o.attribute("systemItem") { return Self.words(s) }
            return o.attribute("customClass") ?? kindName(o)
        }
        if o.element != "scene", !isController(o), o.attribute("customClass") == nil, (o.attribute("title") ?? o.attribute("text")) == nil {
            return kindName(o)
        }
        return o.displayName
    }

    static let kindNames: [String: String] = {
        var count: [String: Int] = [:]
        for k in NewObject.allCases { count[k.element, default: 0] += 1 }
        var out: [String: String] = [:]
        for k in NewObject.allCases where count[k.element] == 1 { out[k.element] = k.rawValue }
        return out
    }()

    public func kindName(_ o: Object) -> String {
        switch (o.element, o.key) {
        case ("viewLayoutGuide", "contentLayoutGuide"): return "Content Layout Guide"
        case ("viewLayoutGuide", "frameLayoutGuide"): return "Frame Layout Guide"
        case ("view", "contentView"): return "Content View"
        case ("stackView", _): return o.attribute("axis") == "vertical" ? "Vertical Stack View" : "Horizontal Stack View"
        case ("menu", _): return o.node.child("menuOptions")?["displayInline"] == "YES" ? "Inline Section Menu" : "Menu"
        case ("visualEffectView", _): return "Visual Effect View"
        case ("barButtonItem", _): return "Bar Button Item"
        default: return Self.kindNames[o.element] ?? Self.words(o.element)
        }
    }

    public func outlineBadge(_ o: Object) -> String? {
        guard o.attribute("userLabel") == nil, isSubview(o), content(of: o) != nil else { return nil }
        return o.attribute("customClass") ?? Self.words(o.element)
    }

    public func outlineChildren(_ o: Object) -> [Object] {
        func rank(_ c: Object) -> Int {
            if c.element == "viewLayoutGuide" { return 0 }
            if c.attribute("sceneMemberID") == "firstResponder" || c.attribute("placeholderIdentifier") == "IBFirstResponder" { return 2 }
            if c.element == "exit" || c.attribute("sceneMemberID") == "exit" { return 3 }
            return 1
        }
        return o.children.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    public func isInitialScene(_ scene: Object) -> Bool {
        guard isStoryboard, let i = initialViewController else { return false }
        return scene.children.contains { $0.id == i }
    }

    public func outlinePath(to o: Object) -> [String] {
        var out: [String] = []
        var cur: Object? = o
        while let c = cur { out.insert(outlineTitle(c), at: 0); cur = c.parent }
        return out
    }
}
