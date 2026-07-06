import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        SidebarCommands()

        CommandGroup(replacing: .newItem) {
            Button("New Project...") {
                NotificationCenter.default.post(name: NSNotification.Name("ShowNewProjectSheet"), object: nil)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Open...") {
                NotificationCenter.default.post(name: NSNotification.Name("ShowImportPicker"), object: nil)
            }
            .keyboardShortcut("o", modifiers: [.command])
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") {
                NotificationCenter.default.post(name: NSNotification.Name("ToggleInspector"), object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }

        CommandMenu("Project") {
            Button("Run Build") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "build_trigger"])
            }
            .keyboardShortcut("b", modifiers: [.command])

            Button("Run Tests") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "run_tests"])
            }
            .keyboardShortcut("u", modifiers: [.command])

            Divider()

            Button("AI Agent") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectSidebarItem"), object: nil, userInfo: ["item": "agent"])
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Go to Line...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "go_to_line"])
            }
            .keyboardShortcut("l", modifiers: [.command])
        }
    }
}
