import SwiftUI

struct StoreKitSidebarView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var workspaceManager = StoreKitWorkspaceManager.shared
    @State private var simulationService = StoreKitSimulationService.shared
    @State private var hoverItem: String? = nil

    private let categories: [StoreKitSidebarSection] = [
        StoreKitSidebarSection(title: "WORKSPACE", items: [
            StoreKitSidebarItem(name: "Dashboard", icon: "square.dashboard", targetSection: "Dashboard"),
            StoreKitSidebarItem(name: "StoreKit Explorer", icon: "folder", targetSection: "Explorer"),
            StoreKitSidebarItem(name: "Starter Templates", icon: "square.grid.3x1.below.line.grid.1x2", targetSection: "Templates"),
            StoreKitSidebarItem(name: "Version History", icon: "clock.arrow.circlepath", targetSection: "Version History"),
            StoreKitSidebarItem(name: "Compare Configs", icon: "arrow.2.squarepath", targetSection: "Compare View")
        ]),
        StoreKitSidebarSection(title: "PRODUCTS", items: [
            StoreKitSidebarItem(name: "Product Library", icon: "cart", targetSection: "Products"),
            StoreKitSidebarItem(name: "Consumables", icon: "flame", targetSection: "Consumables"),
            StoreKitSidebarItem(name: "Non Consumables", icon: "sparkles", targetSection: "Non Consumables"),
            StoreKitSidebarItem(name: "Auto Renewables", icon: "arrow.3.clockwise", targetSection: "Auto Renewables"),
            StoreKitSidebarItem(name: "Non Renewables", icon: "hourglass", targetSection: "Non Renewables")
        ]),
        StoreKitSidebarSection(title: "MANAGEMENT", items: [
            StoreKitSidebarItem(name: "Subscription Groups", icon: "square.stack.3d.up", targetSection: "Subscription Groups"),
            StoreKitSidebarItem(name: "Subscription Timeline", icon: "chart.bar.doc.horizontal", targetSection: "Subscription Timeline"),
            StoreKitSidebarItem(name: "Offers & Designers", icon: "tag", targetSection: "Offers"),
            StoreKitSidebarItem(name: "Storefront Manager", icon: "globe", targetSection: "Storefronts"),
            StoreKitSidebarItem(name: "Localization Matrix", icon: "character.bubble", targetSection: "Localization"),
            StoreKitSidebarItem(name: "Asset & Screenshot", icon: "photo", targetSection: "Assets")
        ]),
        StoreKitSidebarSection(title: "TESTING & UTILITIES", items: [
            StoreKitSidebarItem(name: "Purchase Simulator", icon: "play.circle", targetSection: "Purchase Simulator"),
            StoreKitSidebarItem(name: "Transaction Explorer", icon: "scroll", targetSection: "Transactions"),
            StoreKitSidebarItem(name: "Health & Validation", icon: "exclamationmark.shield", targetSection: "Validation"),
            StoreKitSidebarItem(name: "Global Search Center", icon: "magnifyingglass", targetSection: "Search Center"),
            StoreKitSidebarItem(name: "Command Palette", icon: "terminal", targetSection: "Command Palette")
        ]),
        StoreKitSidebarSection(title: "ADVANCED", items: [
            StoreKitSidebarItem(name: "Workspace Logs", icon: "terminal.fill", targetSection: "Logs"),
            StoreKitSidebarItem(name: "Raw Source Editor", icon: "chevron.left.forwardslash.chevron.right", targetSection: "Raw Source"),
            StoreKitSidebarItem(name: "Settings", icon: "gearshape", targetSection: "Settings")
        ])
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Native-Styled Title Bar Block
            HStack(spacing: 10) {
                Image(systemName: "receipt")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("StoreKit Environment")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Xcode Grade IDE Suite")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()

                // Recent Files Picker
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
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Main Sidebar List
            List {
                // Pin/Favorites Section (if there are active favorites)
                if !simulationService.favoriteProducts.isEmpty {
                    Section(header: Text("FAVORITES")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)) {
                            ForEach(Array(simulationService.favoriteProducts), id: \.self) { favID in
                                HStack(spacing: 8) {
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.orange)
                                    Text(favID)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                                .cornerRadius(4)
                                .onTapGesture {
                                    session.selectedSection = "Products"
                                }
                            }
                        }
                }

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
    private func sidebarRow(_ item: StoreKitSidebarItem) -> some View {
        let isSelected = session.selectedSection == item.targetSection
        HStack(spacing: 8) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .frame(width: 16)
                .foregroundColor(isSelected ? .white : .accentColor)

            Text(item.name)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .lineLimit(1)
                .foregroundColor(isSelected ? .white : .primary)

            Spacer()

            // Sub-Count notification badges for warnings or items
            if item.targetSection == "Validation" {
                let issuesCount = StoreKitValidationService.shared.validate(config: session.activeConfig).count
                if issuesCount > 0 {
                    Text("\(issuesCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isSelected ? .accentColor : .white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(isSelected ? Color.white : Color.orange, in: Capsule())
                }
            } else if item.targetSection == "Transactions" {
                let txCount = simulationService.transactions.count
                if txCount > 0 {
                    Text("\(txCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
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

struct StoreKitSidebarSection: Identifiable {
    var id = UUID()
    var title: String
    var items: [StoreKitSidebarItem]
}

struct StoreKitSidebarItem: Identifiable {
    var id: String { name }
    var name: String
    var icon: String
    var targetSection: String
}
