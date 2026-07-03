import SwiftUI

struct AppCommands: Commands {
    var body: some Commands {
        SidebarCommands()
        CommandGroup(replacing: .newItem) {
            Button("New Project...") { }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Folder...") { }
                .keyboardShortcut("o", modifiers: [.command])
        }
    }
}
