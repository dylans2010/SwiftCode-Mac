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

            Button("Command Palette...") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "command_palette"])
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
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

        CommandMenu("Workspace") {
            Button("Open WorkspaceView") {
                openWorkspaceView()
            }
            .keyboardShortcut("0", modifiers: [.command, .shift])
        }

        CommandMenu("Git Operations") {
            Button("Commit...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Commit"])
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Button("Push...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Push"])
            }
            .keyboardShortcut("h", modifiers: [.command, .shift])

            Button("Push Options...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Push Options"])
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("Choose Branch...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Choose Branch"])
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])

            Button("Include Tags...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Include Tags"])
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])

            Button("Force Push...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Force Push"])
            }
            .keyboardShortcut("y", modifiers: [.command, .shift])

            Button("Fetch...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Fetch"])
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])

            Button("Pull...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Pull"])
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Button("Cherry Pick...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Cherry Pick"])
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])

            Button("Clone...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Clone"])
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])

            Button("Create Repository...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Create Repository"])
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Create Branch...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Create Branch"])
            }
            .keyboardShortcut("j", modifiers: [.command, .shift])

            Button("Switch Branch...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Switch Branch"])
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Button("Delete Branch...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Delete Branch"])
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Stash...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Stash"])
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])

            Button("Apply Stash...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Apply Stash"])
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button("Rebase...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Rebase"])
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])

            Button("Merge...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Merge"])
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Discard Changes...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Discard Changes"])
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Button("Create PR...") {
                NotificationCenter.default.post(name: NSNotification.Name("SelectMenuBarTab"), object: nil, userInfo: ["tab": "Create PR"])
            }
            .keyboardShortcut("q", modifiers: [.command, .shift])
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

            Divider()

            Button("Terminal 2.0") {
                NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "terminal"])
            }
            .keyboardShortcut("t", modifiers: [.command, .shift])
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
