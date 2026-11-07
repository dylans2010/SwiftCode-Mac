import Foundation
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

public struct OutlineGroup<Data: RandomAccessCollection, ID: Hashable, Parent, Leaf, Subgroup> {
    let data: Data
    let children: KeyPath<Data.Element, Data?>
    let idOf: (Data.Element) -> ID
    let content: (Data.Element) -> Leaf
}

public struct OutlineSubgroupChildren: View {
    let view: AnyView
    public var body: some View { view }
}

extension OutlineGroup where ID == Data.Element.ID, Parent: View, Parent == Leaf,
    Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>, Leaf: View, Data.Element: Identifiable {
    public init(_ data: Data, children: KeyPath<Data.Element, Data?>, @ViewBuilder content: @escaping (Data.Element) -> Leaf) {
        self.data = data
        self.children = children
        idOf = { $0.id }
        self.content = content
    }
}

extension OutlineGroup where Parent: View, Parent == Leaf, Subgroup == DisclosureGroup<Parent, OutlineSubgroupChildren>,
    Leaf: View {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, children: KeyPath<Data.Element, Data?>,
                @ViewBuilder content: @escaping (Data.Element) -> Leaf) {
        self.data = data
        self.children = children
        let kp = UncheckedKeyPath(id)
        idOf = { $0[keyPath: kp.value] }
        self.content = content
    }
}

private struct UncheckedKeyPath<Root, Value>: @unchecked Sendable {
    let value: KeyPath<Root, Value>
    init(_ v: KeyPath<Root, Value>) { value = v }
}

extension OutlineGroup: View where Parent: View, Leaf: View, Subgroup: View {
    public var body: some View {
        let children = children, content = content, idOf = idOf
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(data.enumerated()), id: \.offset) { pair in
                OutlineNodeView(element: pair.element, id: AnyHashable(idOf(pair.element)), children: children,
                                idOf: { AnyHashable(idOf($0)) }, content: { AnyView(content($0)) })
            }
        }
    }
}

private struct OutlineNodeView<Element, Data: RandomAccessCollection>: View where Data.Element == Element {
    let element: Element
    let id: AnyHashable
    let children: KeyPath<Element, Data?>
    let idOf: (Element) -> AnyHashable
    let content: (Element) -> AnyView

    var body: some View {
        if let kids = element[keyPath: children] {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(kids.enumerated()), id: \.offset) { pair in
                        AnyView(OutlineNodeView(element: pair.element, id: idOf(pair.element), children: children,
                                                idOf: idOf, content: content))
                    }
                }
            } label: {
                content(element)
            }
        } else {
            content(element)
        }
    }
}

extension OutlineGroup: LazyItemEnumerating where Leaf: View {
    package func _lazyItems(prefix: [AnyHashable], into items: inout LazyItems, context: LazyEnumerationContext) {
        func add(_ elements: Data, depth: Int, parent: AnyHashable?) {
            for element in elements {
                let id = AnyHashable(idOf(element))
                let key = AnyHashable(prefix + [id])
                let kids = element[keyPath: children]
                let expanded = kids != nil && context.isExpanded(key, default: context.initiallyExpanded(id))
                let content = content
                var item = LazyItem(key: key, id: id, make: { content(element) })
                item.depth = depth
                item.outline = .init(hasChildren: kids != nil, isExpanded: expanded,
                                     toggle: { context.toggle(key, current: expanded) }, parentKey: parent)
                items.append(item)
                if expanded, let kids { add(kids, depth: depth + 1, parent: key) }
            }
        }
        add(data, depth: context.depth, parent: context.parentKey)
    }
}

public struct DisclosureGroup<Label: View, Content: View>: View {
    let label: Label
    let content: () -> Content
    let isExpanded: Binding<Bool>?
    @State private var expandedState = false

    public init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content
        isExpanded = nil
    }

    public init(isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: () -> Label) {
        self.label = label()
        self.content = content
        self.isExpanded = isExpanded
    }

    private var expanded: Bool { isExpanded?.wrappedValue ?? expandedState }

    private func toggle() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if let b = isExpanded { b.wrappedValue.toggle() } else { expandedState.toggle() }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .resizable()
                    .frame(width: 9, height: 9)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .frame(width: 12, height: 16)
                label
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle() }
            if expanded {
                content().padding(.leading, 18)
            }
        }
    }
}

extension DisclosureGroup where Label == Text {
    public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(titleKey) }
    }

    public init(_ titleKey: LocalizedStringKey, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(titleKey) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, @ViewBuilder content: @escaping () -> Content) {
        self.init(content: content) { Text(title) }
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, isExpanded: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self.init(isExpanded: isExpanded, content: content) { Text(title) }
    }
}

extension DisclosureGroup: LazyItemEnumerating {
    package func _lazyItems(prefix: [AnyHashable], into items: inout LazyItems, context: LazyEnumerationContext) {
        let key = AnyHashable(prefix)
        let binding = isExpanded
        let id = context.takeElementID()
        let expanded = binding?.wrappedValue ?? context.isExpanded(key, default: context.initiallyExpanded(id))
        let label = label
        var item = LazyItem(key: AnyHashable(prefix + [AnyHashable("label")]), id: id, make: { label })
        item.depth = context.depth
        item.outline = .init(hasChildren: true, isExpanded: expanded, toggle: {
            if let b = binding {
                b.wrappedValue.toggle()
            } else {
                context.toggle(key, current: expanded)
            }
        }, parentKey: context.parentKey)
        items.append(item)
        guard expanded else { return }
        let saved = (context.depth, context.parentKey)
        context.depth += 1
        context.parentKey = item.key
        enumerateLazyItems(content(), prefix: prefix + [AnyHashable("content")], into: &items, context: context)
        (context.depth, context.parentKey) = saved
    }
}

@MainActor @preconcurrency
public protocol DisclosureGroupStyle {}

public struct AutomaticDisclosureGroupStyle: DisclosureGroupStyle {
    public init() {}
}

extension DisclosureGroupStyle where Self == AutomaticDisclosureGroupStyle {
    public static var automatic: AutomaticDisclosureGroupStyle { AutomaticDisclosureGroupStyle() }
}

extension View {
    public func disclosureGroupStyle<S: DisclosureGroupStyle>(_ style: S) -> some View { self }
}
