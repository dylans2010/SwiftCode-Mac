import SwiftUI

struct StoreKitSidebarView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var workspaceManager = StoreKitWorkspaceManager.shared
    @State private var hoverItem: String? = nil

    private let categories: [SidebarSection] = [
        SidebarSection(title: "WORKSPACE", items: [
            SidebarItem(name: "Dashboard", icon: "square.dashboard", targetSection: "Dashboard"),
            SidebarItem(name: "Templates", icon: "square.grid.3x1.below.line.grid.1x2", targetSection: "Templates")
        ]),
        SidebarSection(title: "PRODUCTS", items: [
            SidebarItem(name: "All Products", icon: "cart", targetSection: "Products"),
            SidebarItem(name: "Consumables", icon: "flame", targetSection: "Consumables"),
            SidebarItem(name: "Non Consumables", icon: "sparkles", targetSection: "Non Consumables"),
            SidebarItem(name: "Auto Renewables", icon: "arrow.3.clockwise", targetSection: "Auto Renewables"),
            SidebarItem(name: "Non Renewables", icon: "hourglass", targetSection: "Non Renewables")
        ]),
        SidebarSection(title: "MANAGEMENT", items: [
            SidebarItem(name: "Subscription Groups", icon: "square.stack.3d.up", targetSection: "Subscription Groups"),
            SidebarItem(name: "Offers & Codes", icon: "tag", targetSection: "Offers"),
            SidebarItem(name: "Storefronts", icon: "globe", targetSection: "Storefronts"),
            SidebarItem(name: "Localization", icon: "character.bubble", targetSection: "Localization"),
            SidebarItem(name: "Assets & Media", icon: "photo", targetSection: "Assets")
        ]),
        SidebarSection(title: "TESTING & SIMULATION", items: [
            SidebarItem(name: "Purchase Simulator", icon: "play.circle", targetSection: "Purchase Simulator"),
            SidebarItem(name: "Transactions", icon: "scroll", targetSection: "Transactions"),
            SidebarItem(name: "Validation & Diagnostics", icon: "exclamationmark.shield", targetSection: "Validation")
        ]),
        SidebarSection(title: "UTILITIES", items: [
            SidebarItem(name: "Workspace Logs", icon: "terminal", targetSection: "Logs"),
            SidebarItem(name: "Raw Source Editor", icon: "chevron.left.forwardslash.chevron.right", targetSection: "Raw Source"),
            SidebarItem(name: "Settings", icon: "gearshape", targetSection: "Settings")
        ])
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Sidebar Header with Recent Files picker
            HStack {
                Image(systemName: "receipt")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("StoreKit Editor")
                        .font(.headline)
                        .lineLimit(1)
                    Text("v4.0 Production Grade")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Recent Files Menu
                Menu {
                    Button("Create New Configuration") {
                        session.loadDefaultWorkspace()
                    }
                    Divider()
                    if workspaceManager.recentFiles.isEmpty {
                        Text("No Recent Files")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(workspaceManager.recentFiles, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                session.loadDocument(from: url)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main Sidebar List
            List {
                ForEach(categories) { section in
                    Section(header: Text(section.title)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)) {
                            ForEach(section.items) { item in
                                sidebarRow(item)
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    @ViewBuilder
    private func sidebarRow(_ item: SidebarItem) -> some View {
        let isSelected = session.selectedSection == item.targetSection
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 13))
                .frame(width: 16)
                .foregroundColor(isSelected ? .white : .accentColor)

            Text(item.name)
                .font(.subheadline)
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor : (hoverItem == item.id ? Color.secondary.opacity(0.12) : Color.clear))
        .cornerRadius(6)
        .onHover { hovering in
            hoverItem = hovering ? item.id : nil
        }
        .onTapGesture {
            session.selectedSection = item.targetSection
        }
    }
}

// Sidebar structural helpers

struct SidebarSection: Identifiable {
    var id = UUID()
    var title: String
    var items: [SidebarItem]
}

struct SidebarItem: Identifiable {
    var id: String { name }
    var name: String
    var icon: String
    var targetSection: String
}
