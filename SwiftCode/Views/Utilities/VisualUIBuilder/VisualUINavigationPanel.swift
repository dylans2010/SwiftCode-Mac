import SwiftUI

/// Navigation flow editor displaying active transitions, destinations, and sheet triggers
public struct VisualUINavigationPanel: View {
    let document: VisualUIDocument
    let node: VisualComponentNode

    public var body: some View {
        GroupBox("Navigation Actions") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Configure action click response:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Action Type:", selection: Binding(
                    get: { node.properties["navigationType"] ?? "None" },
                    set: { node.properties["navigationType"] = $0 }
                )) {
                    Text("None").tag("None")
                    Text("Push Navigation").tag("Push")
                    Text("Present Sheet").tag("Sheet")
                    Text("Dismiss Screen").tag("Dismiss")
                }

                let navType = node.properties["navigationType"] ?? "None"
                if navType == "Push" || navType == "Sheet" {
                    Picker("Destination:", selection: Binding(
                        get: { node.properties["navigationDestination"] ?? "" },
                        set: { node.properties["navigationDestination"] = $0 }
                    )) {
                        Text("Choose Screen").tag("")
                        ForEach(document.scene.artboards) { artboard in
                            Text(artboard.name).tag(artboard.id.uuidString)
                        }
                    }
                }
            }
        }
    }
}
