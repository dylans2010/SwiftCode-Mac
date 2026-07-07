import SwiftUI

struct GitCheatsheetView: View {
    struct GitCommand: Identifiable {
        let id = UUID()
        let command: String
        let description: String
        let category: String
    }

    let commands = [
        GitCommand(command: "git init", description: "Initialize a local Git repository", category: "Setup"),
        GitCommand(command: "git clone <url>", description: "Create a local copy of a remote repository", category: "Setup"),
        GitCommand(command: "git add <file>", description: "Add a file to the staging area", category: "Snapshots"),
        GitCommand(command: "git commit -m \"message\"", description: "Commit staged changes with a message", category: "Snapshots"),
        GitCommand(command: "git status", description: "Show the status of your working directory", category: "Snapshots"),
        GitCommand(command: "git log", description: "Show commit history", category: "Snapshots"),
        GitCommand(command: "git branch", description: "List, create, or delete branches", category: "Branches"),
        GitCommand(command: "git checkout <branch>", description: "Switch to a specific branch", category: "Branches"),
        GitCommand(command: "git merge <branch>", description: "Merge a branch into the current branch", category: "Branches"),
        GitCommand(command: "git push <remote> <branch>", description: "Push local commits to a remote repository", category: "Remote"),
        GitCommand(command: "git pull", description: "Fetch and merge changes from a remote repository", category: "Remote"),
        GitCommand(command: "git remote -v", description: "List remote repositories", category: "Remote"),
        GitCommand(command: "git stash", description: "Temporarily store uncommitted changes", category: "Utilities"),
        GitCommand(command: "git reset --hard", description: "Discard all local changes", category: "Utilities"),
        GitCommand(command: "git diff", description: "Show changes between commits, commit and working tree, etc", category: "Utilities")
    ]

    var categories: [String] {
        Array(Set(commands.map { $0.category })).sorted()
    }

    var body: some View {
        List {
            ForEach(categories, id: \.self) { category in
                Section(header: Text(category).font(.headline)) {
                    ForEach(commands.filter { $0.category == category }) { command in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(command.command)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(.accentColor)
                            Text(command.description)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        .contextMenu {
                            Button("Copy Command") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command.command, forType: .string)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Git Cheatsheet")
    }
}
