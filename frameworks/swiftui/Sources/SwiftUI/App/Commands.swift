import Foundation
import Observation
import OVPlatform
#if OPENVIEWS_RENAMED
import OpenViewsCore
#else
import SwiftUICore
#endif

@MainActor @preconcurrency
public protocol Commands {
    associatedtype Body: Commands
    @CommandsBuilder @MainActor @preconcurrency var body: Body { get }
}

extension Never: Commands {}

extension Commands where Body == Never {
    public var body: Never { fatalError("\(Self.self) is primitive commands") }
}

@MainActor @resultBuilder
public struct CommandsBuilder {
    public static func buildExpression<Content: Commands>(_ content: Content) -> Content { content }
    public static func buildBlock() -> EmptyCommands { EmptyCommands() }
    public static func buildBlock<Content: Commands>(_ content: Content) -> Content { content }
    public static func buildBlock<each Content: Commands>(_ content: repeat each Content) -> _TupleCommands {
        var items: [any Commands] = []
        repeat items.append(each content)
        return _TupleCommands(items: items)
    }
    public static func buildOptional(_ content: (any Commands)?) -> _TupleCommands {
        _TupleCommands(items: content.map { [$0] } ?? [])
    }
    public static func buildEither<First: Commands>(first: First) -> _TupleCommands { _TupleCommands(items: [first]) }
    public static func buildEither<Second: Commands>(second: Second) -> _TupleCommands { _TupleCommands(items: [second]) }
    public static func buildLimitedAvailability<Content: Commands>(_ content: Content) -> _TupleCommands {
        _TupleCommands(items: [content])
    }
}

public struct EmptyCommands: Commands {
    public init() {}
    public typealias Body = Never
}

public struct _TupleCommands: Commands {
    let items: [any Commands]
    public typealias Body = Never
}

public struct CommandGroupPlacement: Sendable, Hashable {
    let id: String
    init(_ id: String) { self.id = id }

    public static let appInfo = CommandGroupPlacement("appInfo")
    public static let appSettings = CommandGroupPlacement("appSettings")
    public static let systemServices = CommandGroupPlacement("systemServices")
    public static let appVisibility = CommandGroupPlacement("appVisibility")
    public static let appTermination = CommandGroupPlacement("appTermination")
    public static let newItem = CommandGroupPlacement("newItem")
    public static let saveItem = CommandGroupPlacement("saveItem")
    public static let importExport = CommandGroupPlacement("importExport")
    public static let printItem = CommandGroupPlacement("printItem")
    public static let undoRedo = CommandGroupPlacement("undoRedo")
    public static let pasteboard = CommandGroupPlacement("pasteboard")
    public static let textEditing = CommandGroupPlacement("textEditing")
    public static let textFormatting = CommandGroupPlacement("textFormatting")
    public static let toolbar = CommandGroupPlacement("toolbar")
    public static let sidebar = CommandGroupPlacement("sidebar")
    public static let windowSize = CommandGroupPlacement("windowSize")
    public static let windowArrangement = CommandGroupPlacement("windowArrangement")
    public static let windowList = CommandGroupPlacement("windowList")
    public static let singleWindowList = CommandGroupPlacement("singleWindowList")
    public static let help = CommandGroupPlacement("help")
}

package enum CommandContribution {
    package enum Position: Sendable { case before, after, replacing }
    case menu(title: String, content: AnyView)
    case group(placement: CommandGroupPlacement, position: Position, content: AnyView)
    case standard(String)
    case removeDefaults
}

@MainActor
package protocol PrimitiveCommands: Commands {
    func _contribution() -> CommandContribution?
    func _children() -> [(AnyHashable, any Commands)]
}

extension PrimitiveCommands {
    package func _contribution() -> CommandContribution? { nil }
    package func _children() -> [(AnyHashable, any Commands)] { [] }
}

extension EmptyCommands: PrimitiveCommands {}

extension _TupleCommands: PrimitiveCommands {
    package func _children() -> [(AnyHashable, any Commands)] {
        items.enumerated().map { (AnyHashable($0.offset), $0.element) }
    }
}

public struct CommandMenu<Content: View>: Commands, PrimitiveCommands {
    let title: String
    let content: Content

    public init(_ nameKey: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        title = Text(nameKey).plainString
        self.content = content()
    }

    public init(_ name: Text, @ViewBuilder content: () -> Content) {
        title = name.plainString
        self.content = content()
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ name: S, @ViewBuilder content: () -> Content) {
        title = String(name)
        self.content = content()
    }

    public typealias Body = Never

    package func _contribution() -> CommandContribution? { .menu(title: title, content: AnyView(content)) }
}

public struct CommandGroup<Content: View>: Commands, PrimitiveCommands {
    let placement: CommandGroupPlacement
    let position: CommandContribution.Position
    let content: Content

    public init(before group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        placement = group
        position = .before
        content = addition()
    }

    public init(after group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        placement = group
        position = .after
        content = addition()
    }

    public init(replacing group: CommandGroupPlacement, @ViewBuilder addition: () -> Content) {
        placement = group
        position = .replacing
        content = addition()
    }

    public typealias Body = Never

    package func _contribution() -> CommandContribution? {
        .group(placement: placement, position: position, content: AnyView(content))
    }
}

public struct SidebarCommands: Commands, PrimitiveCommands {
    public init() {}
    public typealias Body = Never
    package func _contribution() -> CommandContribution? { .standard("sidebar") }
}

public struct ToolbarCommands: Commands, PrimitiveCommands {
    public init() {}
    public typealias Body = Never
    package func _contribution() -> CommandContribution? { .standard("toolbar") }
}

public struct TextEditingCommands: Commands, PrimitiveCommands {
    public init() {}
    public typealias Body = Never
    package func _contribution() -> CommandContribution? { .standard("textEditing") }
}

public struct TextFormattingCommands: Commands, PrimitiveCommands {
    public init() {}
    public typealias Body = Never
    package func _contribution() -> CommandContribution? { .standard("textFormatting") }
}

public struct InspectorCommands: Commands, PrimitiveCommands {
    public init() {}
    public typealias Body = Never
    package func _contribution() -> CommandContribution? { .standard("inspector") }
}

public struct ImportFromDevicesCommands: Commands, PrimitiveCommands {
    public init() {}
    public typealias Body = Never
}

struct RemoveDefaultCommands: Commands, PrimitiveCommands {
    typealias Body = Never
    func _contribution() -> CommandContribution? { .removeDefaults }
}

extension Scene {
    public func commands<Content: Commands>(@CommandsBuilder content: () -> Content) -> _ModifiedScene<Self> {
        let c = content()
        return _ModifiedScene(content: self) { $0.commands.append(c) }
    }

    public func commandsRemoved() -> _ModifiedScene<Self> {
        _ModifiedScene(content: self) { $0.commands.append(RemoveDefaultCommands()) }
    }

    public func commandsReplaced<Content: Commands>(@CommandsBuilder content: () -> Content) -> _ModifiedScene<Self> {
        let c = content()
        return _ModifiedScene(content: self) {
            $0.commands.append(RemoveDefaultCommands())
            $0.commands.append(c)
        }
    }
}

@MainActor
@Observable
package final class CommandsModel {
    package private(set) var revision = 0
    @ObservationIgnored private var contributions: [ObjectIdentifier: (node: WeakNode, value: CommandContribution)] = [:]
    @ObservationIgnored weak var root: ViewNode?

    package init() {}

    func set(_ node: ViewNode, _ c: CommandContribution?) {
        let id = ObjectIdentifier(node)
        if let c { contributions[id] = (WeakNode(node), c) } else if contributions[id] != nil { contributions[id] = nil }
        revision += 1
    }

    package var ordered: [CommandContribution] {
        guard let root else { return [] }
        var out: [CommandContribution] = []
        root.forEachNode { n in
            if let c = contributions[ObjectIdentifier(n)], c.node.node === n { out.append(c.value) }
        }
        return out
    }
}

private enum InCommandHostKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    package var _inCommandHost: Bool {
        get { self[InCommandHostKey.self] }
        set { self[InCommandHostKey.self] = newValue }
    }
}

struct CommandsNodeView<C: Commands>: View, PrimitiveView {
    let commands: C
    let model: CommandsModel
    typealias Body = Never

    private func build(_ node: ViewNode, first: Bool, transaction: Transaction) {
        if let p = commands as? any PrimitiveCommands {
            let contribution = p._contribution()
            model.set(node, contribution)
            var items: [(AnyHashable, any View)] = p._children().map { key, child in
                (key, makeCommandsNode(child, model))
            }
            switch contribution {
            case .menu(_, let content)?, .group(_, _, let content)?:
                items.append((AnyHashable("items"), content.environment(\._inCommandHost, true)))
            default: break
            }
            node.reconcileChildren(items, transaction: transaction)
        } else {
            let c = commands, m = model
            node.updateTracked(inputs: c, inputsChanged: first, transaction: transaction) {
                makeCommandsNode(c.body, m)
            }
        }
    }

    func _makeChildren(node: ViewNode, old: CommandsNodeView?, transaction: Transaction) {
        build(node, first: true, transaction: transaction)
    }

    func _refresh(node: ViewNode, environmentChanged: Bool, transaction: Transaction) {
        if commands is any PrimitiveCommands {
            node.refreshChildren(transaction: transaction)
        } else {
            build(node, first: false, transaction: transaction)
        }
    }

    func _lower(node: ViewNode) -> [LayoutNode] { [] }

    func _removed(node: ViewNode) { model.set(node, nil) }
}

extension CommandsNodeView: GraphInputComparable {
    nonisolated func _isGraphInputEqual(to other: Any) -> Bool { false }
}

@MainActor
func makeCommandsNode(_ c: any Commands, _ model: CommandsModel) -> any View {
    func open<C: Commands>(_ c: C) -> any View { CommandsNodeView(commands: c, model: model) }
    return open(c)
}

struct CommandsHostView: View, PrimitiveView {
    let commands: [any Commands]
    let model: CommandsModel
    let actions: AppCommandActions
    typealias Body = Never

    func _makeChildren(node: ViewNode, old: CommandsHostView?, transaction: Transaction) {
        model.root = node
        var items: [(AnyHashable, any View)] = commands.enumerated().map {
            (AnyHashable($0.offset), makeCommandsNode($0.element, model))
        }
        items.append((AnyHashable("standard"), StandardCommandsHost(model: model, actions: actions)))
        node.reconcileChildren(items, transaction: transaction)
    }

    func _lower(node: ViewNode) -> [LayoutNode] { [] }
}

extension CommandsHostView: GraphInputComparable {
    nonisolated func _isGraphInputEqual(to other: Any) -> Bool { false }
}
