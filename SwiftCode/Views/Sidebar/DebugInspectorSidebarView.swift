import SwiftUI

struct DebugInspectorSidebarView: View {
    @Bindable var viewModel: DebugSessionViewModel

    var body: some View {
        VStack {
            List {
                if let session = viewModel.activeSession {
                    Section("Variables") {
                        ForEach(session.variables) { variable in
                            VariableRow(name: variable.name, value: variable.value, type: variable.type)
                        }
                        if session.variables.isEmpty {
                            Text("No variables").foregroundColor(.secondary).font(.caption)
                        }
                    }

                    Section("Call Stack") {
                        ForEach(session.callStack) { frame in
                            CallStackRow(function: frame.function, location: frame.location, isActive: frame.isActive)
                        }
                        if session.callStack.isEmpty {
                            Text("No call stack").foregroundColor(.secondary).font(.caption)
                        }
                    }
                } else {
                    ContentUnavailableView("No Active Session", systemImage: "ant", description: Text("Start debugging to see variables and call stack."))
                }
            }
        }
    }
}

struct VariableRow: View {
    let name: String
    let value: String
    let type: String

    var body: some View {
        HStack {
            Text(name).bold()
            Text(type).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(.accentColor)
        }
    }
}

struct CallStackRow: View {
    let function: String
    let location: String
    var isActive: Bool = false

    var body: some View {
        HStack {
            Image(systemName: isActive ? "arrowtriangle.right.fill" : "circle.fill")
                .font(.system(size: 8))
                .foregroundColor(isActive ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(function).font(.subheadline)
                Text(location).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
