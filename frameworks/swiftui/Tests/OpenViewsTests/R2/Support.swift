import Foundation
import Testing
#if OPENVIEWS_RENAMED
@testable import OpenViewsCore
@testable import OpenViews
#else
@testable import SwiftUICore
@testable import SwiftUI
#endif

@MainActor
final class Log {
    private(set) var entries: [String] = []

    func callAsFunction(_ s: String) { entries.append(s) }

    func take() -> [String] {
        defer { entries = [] }
        return entries
    }
}

@MainActor
extension ViewGraph {
    static func rendered<V: View>(_ view: V, environment: EnvironmentValues = EnvironmentValues(),
                                  layout: HostLayout? = nil) -> ViewGraph {
        let g = ViewGraph(rootView: view, environment: environment, layout: layout)
        g.update()
        return g
    }
}

@MainActor
final class Controls<Value> {
    var binding: Binding<Value>?
    var value: Value {
        get { binding!.wrappedValue }
        set { binding!.wrappedValue = newValue }
    }
}

struct ProbeModifier: PrimitiveModifier {
    let name: String
    func _lower(_ content: [LayoutNode], secondary: () -> [LayoutNode], node: ViewNode) -> [LayoutNode] {
        content.map { $0.probe(name) }
    }
}

extension View {
    func probe(_ name: String) -> some View { modifier(ProbeModifier(name: name)) }
}
