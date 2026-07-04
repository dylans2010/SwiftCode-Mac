import SwiftUI

struct DebugInspectorSidebarView: View {
    @Bindable var viewModel: DebugSessionViewModel

    var body: some View {
        VStack {
            List {
                if let session = viewModel.activeSession {
                    Section("Variables") {
                        // In a real app, we would fetch variables from the debug adapter
                        // For now, we show a placeholder list that mimics real data
                        VariableRow(name: "self", value: "MyApp.ViewController", type: "ViewController")
                        VariableRow(name: "count", value: "42", type: "Int")
                        VariableRow(name: "items", value: "3 elements", type: "[String]")
                    }

                    Section("Call Stack") {
                        CallStackRow(function: "main()", location: "AppDelegate.swift:10")
                        CallStackRow(function: "application(_:didFinishLaunchingWithOptions:)", location: "AppDelegate.swift:25")
                        CallStackRow(function: "viewDidLoad()", location: "ViewController.swift:15", isActive: true)
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
