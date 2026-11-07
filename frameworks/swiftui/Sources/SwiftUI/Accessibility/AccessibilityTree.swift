import Foundation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

package struct AccessibilityElement: CustomStringConvertible {
    package var id: UInt64
    package var role: AccessibilityRole
    package var label: String?
    package var value: String?
    package var hint: String?
    package var identifier: String?
    package var traits: AccessibilityTraits
    package var frame: CGRect
    package var isEnabled = true
    package var isFocused = false
    package var headingLevel: AccessibilityHeadingLevel?
    package var sortPriority: Double = 0
    package var actionNames: [String] = []
    package var isExpanded: Bool?
    package var rangeValue: AccessibilityRangeValue?
    package var children: [AccessibilityElement] = []
    weak var node: ViewNode?
    var actions: [String: @MainActor () -> Void] = [:]
    var adjust: (@MainActor (AccessibilityAdjustmentDirection) -> Void)?

    package var description: String {
        var parts = ["\(role)"]
        if let label { parts.append("label=\(label)") }
        if let value { parts.append("value=\(value)") }
        if let hint { parts.append("hint=\(hint)") }
        if let identifier { parts.append("id=\(identifier)") }
        parts.append("traits=\(AccessibilityTree.traitNames(traits).joined(separator: "+"))")
        return parts.joined(separator: " ")
    }

    package var flattened: [AccessibilityElement] { [self] + children.flatMap(\.flattened) }

    package var exposedElements: [AccessibilityElement] {
        children.flatMap { c -> [AccessibilityElement] in
            let containers: Set<AccessibilityRole> = [.group, .list, .row, .toolbar, .menuBar, .dialog, .alert, .scrollView, .tabList]
            let mine = containers.contains(c.role) && c.label == nil && !c.children.isEmpty ? [] : [c]
            return mine + c.exposedElements
        }
    }
}

@MainActor
package enum AccessibilityTree {
    nonisolated package static func traitNames(_ t: AccessibilityTraits) -> [String] {
        let names: [(AccessibilityTraits, String)] = [
            (.isButton, "button"), (.isHeader, "header"), (.isSelected, "selected"), (.isLink, "link"),
            (.isSearchField, "searchField"), (.isImage, "image"), (.playsSound, "playsSound"),
            (.isKeyboardKey, "keyboardKey"), (.isStaticText, "staticText"), (.isSummaryElement, "summary"),
            (.updatesFrequently, "updatesFrequently"), (.startsMediaSession, "startsMediaSession"),
            (.allowsDirectInteraction, "directInteraction"), (.causesPageTurn, "pageTurn"), (.isModal, "modal"),
            (.isToggle, "toggle"), (.isTabBar, "tabBar"),
        ]
        return names.filter { t.contains($0.0) }.map(\.1)
    }

    package static func build(_ window: WindowHost, title: String = "") -> AccessibilityElement {
        if window.graph.needsUpdate { window.update() }
        var root = AccessibilityElement(id: 1, role: .window, label: title.isEmpty ? nil : title, traits: [],
                                        frame: CGRect(origin: .zero, size: window.size))
        if let r = window.graph.root {
            let focused = window.services.focus.focusedNode
            var b = Builder(mirrorWidth: window.graph.layoutResult?.mirrorWidth, focused: focused)
            root.children = b.elements(r, inherited: AccessibilityAttributes())
        }
        return root
    }

    @discardableResult
    package static func perform(_ action: String, on id: UInt64, in window: WindowHost) -> Bool {
        let tree = build(window)
        guard let e = tree.flattened.first(where: { $0.id == id }) else { return false }
        if let a = e.actions[action] {
            a()
        } else if action == "increment", let adj = e.adjust {
            adj(.increment)
        } else if action == "decrement", let adj = e.adjust {
            adj(.decrement)
        } else {
            return false
        }
        window.update()
        return true
    }

    @MainActor
    struct Builder {
        let mirrorWidth: CGFloat?
        let focused: ViewNode?

        func frame(_ n: ViewNode) -> CGRect? { HitTesting.frame(of: n, mirrorWidth: mirrorWidth) }

        func id(_ n: ViewNode) -> UInt64 { UInt64(UInt(bitPattern: ObjectIdentifier(n).hashValue)) | 2 }

        mutating func elements(_ node: ViewNode, inherited: AccessibilityAttributes) -> [AccessibilityElement] {
            guard node.isAlive, !node.isSuspended else { return [] }
            var attrs = inherited
            if let m = (node.view as? any ModifierAccessing)?._anyModifier as? AccessibilityModifier {
                attrs = inherited.merged(inner: m.attributes)
                if attrs.hidden == true { return [] }
                if let behavior = m.attributes.children ?? (m.attributes.role != nil ? .combine : nil) {
                    var inner = attrs
                    inner.children = nil
                    return [element(node, behavior: behavior, attrs: inner)]
                }
            }
            if node.lastLowered.isEmpty && node.children.isEmpty { return [] }
            if let leaf = leafElement(node, attrs: attrs) { return [leaf] }
            var out: [AccessibilityElement] = []
            var children = node.children
            if node.view is WindowRootView {
                let rank: [AnyHashable: Int] = [AnyHashable("top"): 0, AnyHashable(0): 1, AnyHashable("bottom"): 2]
                children = zip(node.childKeys, node.children).filter { $0.0 != AnyHashable("commands") }
                    .sorted { (rank[$0.0] ?? 3) < (rank[$1.0] ?? 3) }.map(\.1)
            }
            for c in children { out += elements(c, inherited: attrs) }
            return sorted(out)
        }

        func sorted(_ e: [AccessibilityElement]) -> [AccessibilityElement] {
            guard e.contains(where: { $0.sortPriority != 0 }) else { return e }
            return e.enumerated().sorted { a, b in
                a.element.sortPriority != b.element.sortPriority ? a.element.sortPriority > b.element.sortPriority
                    : a.offset < b.offset
            }.map(\.element)
        }

        func leafElement(_ node: ViewNode, attrs: AccessibilityAttributes) -> AccessibilityElement? {
            guard frame(node) != nil else { return nil }
            if let t = node.view as? Text {
                let s = t.resolve(in: node.environment).string
                var e = base(node, role: .staticText, attrs: attrs)
                e.label = attrs.label ?? s
                e.traits = e.traits.union(.isStaticText).union(attrs.addTraits).subtracting(attrs.removeTraits)
                return e
            }
            if let img = node.view as? Image {
                if img.isDecorative && attrs.label == nil { return nil }
                var e = base(node, role: .image, attrs: attrs)
                let own: String?
                switch img.source {
                case .system(let name): own = img.accessibilityLabelText ?? SymbolAccessibilityLabels.label(for: name)
                case .named(let name, _): own = img.accessibilityLabelText ?? name
                default: own = img.accessibilityLabelText
                }
                e.label = attrs.label ?? own
                e.traits = e.traits.union(.isImage).union(attrs.addTraits).subtracting(attrs.removeTraits)
                return e
            }
            return nil
        }

        func base(_ node: ViewNode, role: AccessibilityRole, attrs: AccessibilityAttributes) -> AccessibilityElement {
            var e = AccessibilityElement(id: id(node), role: attrs.role ?? role, label: attrs.label,
                                         value: attrs.value ?? attrs.dynamicValue?(),
                                         hint: attrs.hint, identifier: attrs.identifier, traits: [],
                                         frame: frame(node) ?? .zero)
            e.isEnabled = attrs.isEnabled ?? node.environment.isEnabled
            e.headingLevel = attrs.headingLevel
            e.sortPriority = attrs.sortPriority ?? 0
            e.actions = attrs.actions
            e.adjust = attrs.adjust
            e.node = node
            e.isFocused = isFocused(node)
            e.actionNames = actionNames(attrs)
            e.isExpanded = attrs.isExpanded
            e.rangeValue = attrs.rangeValue?()
            return e
        }

        func isFocused(_ node: ViewNode) -> Bool {
            guard let f = focused else { return false }
            var n: ViewNode? = f
            while let x = n {
                if x === node { return true }
                n = x.parent
            }
            return false
        }

        func actionNames(_ a: AccessibilityAttributes) -> [String] {
            var names = a.actions.keys.sorted { x, y in x == "default" ? true : (y == "default" ? false : x < y) }
            if a.adjust != nil { names += ["increment", "decrement"] }
            return names
        }

        mutating func element(_ node: ViewNode, behavior: AccessibilityChildBehavior,
                              attrs: AccessibilityAttributes) -> AccessibilityElement {
            var inner: [AccessibilityElement] = []
            if behavior.kind != .ignore {
                for c in node.children { inner += elements(c, inherited: AccessibilityAttributes()) }
            }
            var e = base(node, role: attrs.role ?? (behavior.kind == .contain ? .group : .staticText), attrs: attrs)
            switch behavior.kind {
            case .ignore:
                e.traits = attrs.addTraits.subtracting(attrs.removeTraits)
            case .combine:
                let labels = inner.compactMap(\.label).filter { !$0.isEmpty }
                e.label = attrs.label ?? (labels.isEmpty ? nil : labels.joined(separator: ", "))
                if attrs.value == nil {
                    let values = inner.compactMap(\.value)
                    if !values.isEmpty { e.value = values.joined(separator: ", ") }
                }
                var traits: AccessibilityTraits = attrs.role == nil ? inner.reduce([]) { $0.union($1.traits) } : []
                traits.formUnion(attrs.addTraits)
                e.traits = traits.subtracting(attrs.removeTraits)
                if e.identifier == nil { e.identifier = inner.first { $0.identifier != nil }?.identifier }
                for i in inner where e.actions.isEmpty { e.actions = i.actions }
                if e.actionNames.isEmpty { e.actionNames = actionNames(attrs) }
            case .contain:
                e.children = sorted(inner)
                e.traits = attrs.addTraits.subtracting(attrs.removeTraits)
            }
            return e
        }
    }
}

extension WindowHost {
    package func accessibilityTree(title: String = "") -> AccessibilityElement {
        AccessibilityTree.build(self, title: title.isEmpty ? platform.title : title)
    }
}
