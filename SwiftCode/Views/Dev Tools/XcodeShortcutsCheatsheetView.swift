import SwiftUI

struct ShortcutItem: Identifiable, Hashable {
    let id = UUID()
    let keys: String
    let description: String
    let category: String
}

public struct XcodeShortcutsCheatsheetView: View {
    @State private var filterText = ""
    @State private var selectedCategory = "All"

    private let categories = ["All", "Navigation", "Editing", "Build & Run", "Debugging", "Refactoring"]

    private let shortcuts = [
        ShortcutItem(keys: "⌘ + 1 ... 9", description: "Toggle Navigator Sidebar Tabs", category: "Navigation"),
        ShortcutItem(keys: "⌘ + 0", description: "Show/Hide Navigator Sidebar", category: "Navigation"),
        ShortcutItem(keys: "⌥ + ⌘ + 0", description: "Show/Hide Inspector Sidebar", category: "Navigation"),
        ShortcutItem(keys: "⇧ + ⌘ + O", description: "Open Quickly (Search anything)", category: "Navigation"),
        ShortcutItem(keys: "⌥ + ⌘ + ↑/↓", description: "Switch between source and header / counterpart", category: "Navigation"),
        ShortcutItem(keys: "⌃ + 6", description: "Show document structure / jump bar list", category: "Navigation"),
        ShortcutItem(keys: "⌘ + /", description: "Comment / Un-comment Line", category: "Editing"),
        ShortcutItem(keys: "⌃ + I", description: "Re-indent selected code blocks", category: "Editing"),
        ShortcutItem(keys: "⌥ + ⌘ + [ / ]", description: "Move Line Up / Down", category: "Editing"),
        ShortcutItem(keys: "⌘ + [ / ]", description: "Indent / Out-dent selection", category: "Editing"),
        ShortcutItem(keys: "⌃ + ⌘ + E", description: "Edit all instances in scope", category: "Refactoring"),
        ShortcutItem(keys: "⌃ + ⌘ + Click", description: "Jump to Definition", category: "Navigation"),
        ShortcutItem(keys: "⌘ + B", description: "Build Project Target", category: "Build & Run"),
        ShortcutItem(keys: "⌘ + R", description: "Run Active Target Scheme", category: "Build & Run"),
        ShortcutItem(keys: "⌘ + .", description: "Stop Active Build / Running App", category: "Build & Run"),
        ShortcutItem(keys: "⇧ + ⌘ + K", description: "Clean Build Folder", category: "Build & Run"),
        ShortcutItem(keys: "⌘ + U", description: "Run Unit / UI Test Target Suite", category: "Build & Run"),
        ShortcutItem(keys: "⌘ + \\", description: "Toggle Breakpoint on current line", category: "Debugging"),
        ShortcutItem(keys: "⌘ + Y", description: "Enable / Disable all active Breakpoints", category: "Debugging"),
        ShortcutItem(keys: "⇧ + ⌘ + Y", description: "Show / Hide Debug area console", category: "Debugging"),
        ShortcutItem(keys: "⌃ + ⌘ + Y", description: "Continue execution (LLDB)", category: "Debugging"),
        ShortcutItem(keys: "F6", description: "Step Over current line", category: "Debugging"),
        ShortcutItem(keys: "F7", description: "Step Into call", category: "Debugging")
    ]

    private var filteredShortcuts: [ShortcutItem] {
        shortcuts.filter { item in
            let matchesCategory = selectedCategory == "All" || item.category == selectedCategory
            let matchesFilter = filterText.isEmpty ||
                item.keys.lowercased().contains(filterText.lowercased()) ||
                item.description.lowercased().contains(filterText.lowercased())
            return matchesCategory && matchesFilter
        }
    }

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header with search & category filter
            VStack(spacing: 12) {
                HStack {
                    Label("Xcode Keyboard Shortcuts", systemImage: "keyboard")
                        .font(.title2.bold())
                    Spacer()
                }

                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search shortcuts...", text: $filterText)
                            .textFieldStyle(.plain)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))

                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
            }
            .padding()
            .background(.thinMaterial)

            Divider()

            // List of shortcuts
            List {
                ForEach(filteredShortcuts) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.description)
                                .font(.headline)
                            Text(item.category)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }
                        Spacer()
                        Text(item.keys)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.bold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.inset)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
