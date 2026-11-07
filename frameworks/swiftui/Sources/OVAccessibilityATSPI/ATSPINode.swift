import Foundation

public struct ATSPIRect: Hashable, Sendable {
    public var x: Int32
    public var y: Int32
    public var width: Int32
    public var height: Int32
    public init(x: Int32, y: Int32, width: Int32, height: Int32) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let zero = ATSPIRect(x: 0, y: 0, width: 0, height: 0)

    public func contains(x px: Int32, y py: Int32) -> Bool {
        px >= x && py >= y && px < x + width && py < y + height
    }

    func offsetBy(_ dx: Int32, _ dy: Int32) -> ATSPIRect { ATSPIRect(x: x + dx, y: y + dy, width: width, height: height) }
}

public struct ATSPIAction: Hashable, Sendable {
    public var name: String
    public var localizedName: String
    public var description: String
    public var keyBinding: String
    public init(name: String, localizedName: String? = nil, description: String = "", keyBinding: String = "") {
        self.name = name
        self.localizedName = localizedName ?? name
        self.description = description
        self.keyBinding = keyBinding
    }
}

public struct ATSPIText: Hashable, Sendable {
    public var string: String
    public var caret: Int
    public var selection: Range<Int>
    public var isEditable: Bool
    public init(string: String, caret: Int = 0, selection: Range<Int> = 0..<0, isEditable: Bool = false) {
        self.string = string
        self.caret = caret
        self.selection = selection
        self.isEditable = isEditable
    }

    public var scalars: [Unicode.Scalar] { Array(string.unicodeScalars) }
    public var count: Int { string.unicodeScalars.count }
}

public struct ATSPIValue: Hashable, Sendable {
    public var current: Double
    public var minimum: Double
    public var maximum: Double
    public var increment: Double
    public var text: String
    public var isSettable: Bool
    public init(current: Double, minimum: Double, maximum: Double, increment: Double, text: String = "", isSettable: Bool) {
        self.current = current
        self.minimum = minimum
        self.maximum = maximum
        self.increment = increment
        self.text = text
        self.isSettable = isSettable
    }
}

public struct ATSPINode: Hashable, Sendable {
    public var key: String
    public var role: ATSPIRole
    public var name: String
    public var description: String
    public var identifier: String
    public var states: ATSPIStateSet
    public var frame: ATSPIRect
    public var actions: [ATSPIAction]
    public var text: ATSPIText?
    public var value: ATSPIValue?
    public var isSelectionContainer: Bool
    public var attributes: [String: String]
    public var children: [String]
    public internal(set) var parent: String?
    public internal(set) var indexInParent: Int = 0

    public init(key: String, role: ATSPIRole, name: String = "", description: String = "", identifier: String = "",
                states: ATSPIStateSet = ATSPIStateSet(), frame: ATSPIRect = .zero, actions: [ATSPIAction] = [],
                text: ATSPIText? = nil, value: ATSPIValue? = nil, isSelectionContainer: Bool = false,
                attributes: [String: String] = [:], children: [String] = []) {
        self.key = key
        self.role = role
        self.name = name
        self.description = description
        self.identifier = identifier
        self.states = states
        self.frame = frame
        self.actions = actions
        self.text = text
        self.value = value
        self.isSelectionContainer = isSelectionContainer
        self.attributes = attributes
        self.children = children
    }

    public var interfaces: [String] {
        var i = [ATSPI.accessible, ATSPI.component]
        if !actions.isEmpty { i.append(ATSPI.action) }
        if let text {
            i.append(ATSPI.text)
            if text.isEditable { i.append(ATSPI.editableText) }
        }
        if value != nil { i.append(ATSPI.value) }
        if isSelectionContainer { i.append(ATSPI.selection) }
        return i
    }
}

public struct ATSPIWindowSnapshot: Sendable {
    public var rootKey: String
    public var nodes: [String: ATSPINode]
    public var revision: Int

    public init(rootKey: String, nodes: [ATSPINode], revision: Int) {
        self.rootKey = rootKey
        self.revision = revision
        var map: [String: ATSPINode] = [:]
        for n in nodes { map[n.key] = n }
        for n in nodes {
            let kids = n.children.filter { map[$0] != nil }
            map[n.key]?.children = kids
            for (i, c) in kids.enumerated() {
                map[c]?.parent = n.key
                map[c]?.indexInParent = i
            }
        }
        self.nodes = map
    }

    public var orderedKeys: [String] {
        var out: [String] = []
        var stack = [rootKey]
        while let k = stack.popLast() {
            guard let n = nodes[k] else { continue }
            out.append(k)
            stack.append(contentsOf: n.children.reversed())
        }
        return out
    }
}

@MainActor
public protocol ATSPIProvider: AnyObject {
    var applicationName: String { get }
    var toolkitVersion: String { get }
    func windowKeys() -> [String]
    func revision(ofWindow key: String) -> Int
    func snapshot(ofWindow key: String) -> ATSPIWindowSnapshot?
    func screenOrigin(ofWindow key: String) -> (x: Int32, y: Int32)?
    func performAction(_ index: Int, on key: String) -> Bool
    func grabFocus(_ key: String) -> Bool
    func setText(_ text: String, on key: String) -> Bool
    func replaceText(in range: Range<Int>, with text: String, on key: String) -> Bool
    func setSelection(_ range: Range<Int>, on key: String) -> Bool
    func copyText(_ range: Range<Int>, on key: String, cut: Bool) -> Bool
    func pasteText(at offset: Int, on key: String) -> Bool
    func setValue(_ value: Double, on key: String) -> Bool
    func selectChild(_ index: Int, of key: String) -> Bool
}

extension ATSPIProvider {
    public var toolkitVersion: String { "1.0" }
    public func screenOrigin(ofWindow key: String) -> (x: Int32, y: Int32)? { nil }
    public func grabFocus(_ key: String) -> Bool { false }
    public func setText(_ text: String, on key: String) -> Bool { false }
    public func replaceText(in range: Range<Int>, with text: String, on key: String) -> Bool { false }
    public func setSelection(_ range: Range<Int>, on key: String) -> Bool { false }
    public func copyText(_ range: Range<Int>, on key: String, cut: Bool) -> Bool { false }
    public func pasteText(at offset: Int, on key: String) -> Bool { false }
    public func setValue(_ value: Double, on key: String) -> Bool { false }
    public func selectChild(_ index: Int, of key: String) -> Bool { false }
}
