import SwiftUI

struct AppCommands: Commands {
    private var sessionStore = ProjectSessionStore.shared

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

        CommandGroup(after: .saveItem) {
            Button("Save") {
                sessionStore.saveCurrentFile(content: sessionStore.activeFileContent)
            }
            .keyboardShortcut("s", modifiers: [.command])
            .disabled(sessionStore.activeFileNode == nil)

            Button("Save All") {
                sessionStore.saveAll()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(sessionStore.openFileTabs.isEmpty)

            Divider()

            Button("Export Project...") {
                NotificationCenter.default.post(name: NSNotification.Name("ShowExportSheet"), object: nil)
            }

            Divider()

            Button("Close Project") {
                sessionStore.closeProject()
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
            .disabled(sessionStore.activeProject == nil)
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

            Divider()

            Button("Project Settings...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "settings"])
            }
        }

        CommandGroup(after: .textEditing) {
            Button("Go to Line...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "go_to_line"])
            }
            .keyboardShortcut("l", modifiers: [.command])
        }

        CommandMenu("Editor") {
            Button("Find...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "code_search"])
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Go to Line...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "go_to_line"])
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button("Format Code") {
                NotificationCenter.default.post(name: NSNotification.Name("FormatCode"), object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Divider()

            Button("Next Tab") {
                NotificationCenter.default.post(name: NSNotification.Name("NextTab"), object: nil)
            }
            .keyboardShortcut("}", modifiers: [.command, .shift])

            Button("Previous Tab") {
                NotificationCenter.default.post(name: NSNotification.Name("PreviousTab"), object: nil)
            }
            .keyboardShortcut("{", modifiers: [.command, .shift])
        }

        CommandMenu("View") {
            Button("Zoom In") {
                // Implementation would go here
            }
            .keyboardShortcut("+", modifiers: [.command])

            Button("Zoom Out") {
                // Implementation would go here
            }
            .keyboardShortcut("-", modifiers: [.command])
        }

        CommandGroup(replacing: .help) {
            Button("SwiftCode Documentation") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "documentation_browser"])
            }
            Button("Diagnostics") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "error_diagnostics"])
            }
        }
    }
}
