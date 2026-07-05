import SwiftUI

struct StateInspectorView: View {
    @State private var expandedNodes: Set<String> = []

    var body: some View {
        List {
            StateNodeView(name: "AppRoot", value: nil, children: [
                StateNodeView(name: "ProjectManager", value: nil, children: [
                    StateNodeView(name: "currentProject", value: "SwiftCode"),
                    StateNodeView(name: "projectsCount", value: "12")
                ]),
                StateNodeView(name: "SessionManager", value: nil, children: [
                    StateNodeView(name: "isLoggedIn", value: "true"),
                    StateNodeView(name: "currentUser", value: "Developer")
                ]),
                StateNodeView(name: "CollaborationManager", value: nil, children: [
                    StateNodeView(name: "activeUsers", value: "3"),
                    StateNodeView(name: "pendingPRs", value: "1")
                ])
            ])
        }
        .navigationTitle("State Inspector")
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
    }
}

struct StateNodeView: View, Identifiable {
    let id = UUID().uuidString
    let name: String
    let value: String?
    var children: [StateNodeView]? = nil
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if children != nil {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .onTapGesture { isExpanded.toggle() }
                } else {
                    Circle().fill(Color.blue).frame(width: 4, height: 4).padding(.horizontal, 4)
                }

                Text(name)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)

                if let val = value {
                    Spacer()
                    Text(val)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { if children != nil { isExpanded.toggle() } }

            if isExpanded, let children = children {
                VStack(alignment: .leading) {
                    ForEach(children) { child in
                        child.padding(.leading, 16)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
