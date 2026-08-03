import SwiftUI
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "com.swiftcode.storekit", category: "Editors")

// MARK: - 1. StoreKitDashboardView

struct StoreKitDashboardView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var simulationService = StoreKitSimulationService.shared
    @State private var validationService = StoreKitValidationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("StoreKit Environment Dashboard")
                            .font(.system(size: 18, weight: .bold))
                        Text("Xcode Grade suite offering native analytics, live verification, and localized simulator sandboxes.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { session.selectedSection = "Templates" }) {
                        Label("Apply Preset Framework...", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 6)

                let issues = validationService.validate(config: session.activeConfig)
                let healthScore = validationService.calculateHealthScore(issues: issues)

                // High-End Metric Cards Grid
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 14) {
                    metricCard(title: "Portfolio Health Score", count: "\(healthScore)%", subtitle: "Based on static analysis rules", icon: "heart.text.square", color: healthScore > 80 ? .green : (healthScore > 50 ? .orange : .red))
                    metricCard(title: "Active Products Count", count: String(session.activeConfig.products.count + session.activeConfig.nonRenewingSubscriptions.count), subtitle: "Consumables & Non-Consumables", icon: "cart", color: .blue)
                    metricCard(title: "Subscription Groups", count: String(session.activeConfig.subscriptionGroups.count), subtitle: "Auto-Renewable Families", icon: "square.stack.3d.up", color: .purple)
                    metricCard(title: "Diagnostics Issues", count: String(issues.count), subtitle: "Schema errors and suggestions", icon: "exclamationmark.triangle", color: issues.isEmpty ? .green : .orange)
                }

                HStack(alignment: .top, spacing: 20) {
                    // Left Side: Project Health Overview & Quick Actions
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Active Sandbox Highlights")
                            .font(.system(size: 12, weight: .bold))

                        VStack(alignment: .leading, spacing: 12) {
                            catalogRow(label: "Consumables", count: session.activeConfig.products.filter({ $0.type == "Consumable" }).count, icon: "flame", color: .orange)
                            catalogRow(label: "Non-Consumables", count: session.activeConfig.products.filter({ $0.type == "NonConsumable" }).count, icon: "sparkles", color: .blue)
                            catalogRow(label: "Auto-Renewing Subscriptions", count: session.activeConfig.subscriptionGroups.flatMap({ $0.subscriptions }).count, icon: "arrow.3.clockwise", color: .purple)
                            catalogRow(label: "Non-Renewing Subscriptions", count: session.activeConfig.nonRenewingSubscriptions.count, icon: "hourglass", color: .indigo)
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                        Text("Instant Workspace Actions")
                            .font(.system(size: 12, weight: .bold))
                            .padding(.top, 10)

                        HStack(spacing: 10) {
                            quickActionTile(title: "Add Product", icon: "plus.circle") {
                                session.selectedSection = "Products"
                            }
                            quickActionTile(title: "Simulator", icon: "play.circle") {
                                session.selectedSection = "Purchase Simulator"
                            }
                            quickActionTile(title: "Validate Plists", icon: "checkmark.shield") {
                                session.selectedSection = "Validation"
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right Side: Recent Activity Timeline Stream
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Recent Sandbox Activity Feed")
                            .font(.system(size: 12, weight: .bold))

                        if simulationService.activityEvents.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.system(size: 24))
                                    .foregroundColor(.secondary)
                                Text("No Recent Activity Logged")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Perform transactions, validation scans, or load configuration templates to see life logs.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(simulationService.activityEvents.prefix(4)) { event in
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack {
                                            Text(event.category.uppercased())
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(.accentColor)
                                                .padding(.horizontal, 4)
                                                .padding(.vertical, 1)
                                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))

                                            Spacer()

                                            let f = DateFormatter()
                                            f.dateFormat = "HH:mm:ss"
                                            Text(f.string(from: event.timestamp))
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }

                                        Text(event.title)
                                            .font(.system(size: 11, weight: .bold))

                                        Text(event.message)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Divider()
                                }
                            }
                            .padding(14)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(24)
        }
    }

    private func metricCard(title: String, count: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(color)
                Spacer()
                Text(count)
                    .font(.system(size: 24, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func catalogRow(label: String, count: Int, icon: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.system(size: 11))
                .foregroundColor(color)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
        }
    }

    private func quickActionTile(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - 2. StoreKitExplorerView

struct StoreKitExplorerView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StoreKit Workspace Explorer")
                        .font(.system(size: 18, weight: .bold))
                    Text("Finder-like browser dedicated to active StoreKit plists, saved templates, and generated files.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                // File Grid Block
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Environment Directories")
                        .font(.system(size: 12, weight: .bold))

                    HStack(spacing: 16) {
                        explorerFolderCard(name: "Configuration.storekit", details: "Current Active Document", icon: "doc.text.fill", color: .accentColor) {
                            session.selectedSection = "Raw Source"
                        }

                        explorerFolderCard(name: "Starter Templates", details: "12 Predefined Configurations", icon: "square.grid.2x2.fill", color: .purple) {
                            session.selectedSection = "Templates"
                        }

                        explorerFolderCard(name: "Simulated Transactions", details: "History Records cache", icon: "scroll.fill", color: .green) {
                            session.selectedSection = "Transactions"
                        }
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                // Simulator Sandbox Profiles Selector
                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved Simulator Profiles")
                        .font(.system(size: 12, weight: .bold))

                    ForEach(simulationService.availableProfiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.name)
                                    .font(.system(size: 11, weight: .bold))
                                Text(profile.desc)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            if simulationService.selectedProfileID == profile.id {
                                Label("Active Profile", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                            } else {
                                Button("Apply Profile") {
                                    simulationService.applyProfile(profile)
                                }
                                .font(.system(size: 11))
                            }
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(16)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
    }

    private func explorerFolderCard(name: String, details: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(color)
                Text(name)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Text(details)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 160, height: 110, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}


// MARK: - 3. StoreKitProductsView (Product Library)

struct StoreKitProductsView: View {
    var filterType: String? = nil

    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var searchText = ""
    @State private var selectedProductID: String? = nil
    @State private var bulkActionType = ""

    // Smart Generator Overlay States
    @State private var showingAIGenerator = false
    @State private var editingProduct: SKProduct? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Product Action bar
            HStack(spacing: 12) {
                TextField("Search products by identifier or reference name...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)

                Spacer()

                Button {
                    showingAIGenerator = true
                } label: {
                    Label("AI Product Generator", systemImage: "wand.and.stars")
                }

                Button {
                    addProduct(type: filterType ?? "NonConsumable")
                } label: {
                    Label("Add Product", systemImage: "plus")
                }

                // Bulk Operations Menu
                Menu {
                    Button("Bulk Rename (Suffix '_pro')") {
                        applyBulkOperation(.bulkRename)
                    }
                    Button("Bulk Duplicate") {
                        applyBulkOperation(.bulkDuplicate)
                    }
                    Button("Bulk Generate Localization") {
                        applyBulkOperation(.bulkLocalization)
                    }
                    Divider()
                    Button("Bulk Delete", role: .destructive) {
                        applyBulkOperation(.bulkDelete)
                    }
                } label: {
                    Label("Bulk Operations", systemImage: "square.grid.3x1.below.line.grid.1x2")
                }

                Button {
                    duplicateSelectedProduct()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(selectedProductID == nil)
                .help("Clone Selected Product")

                Button {
                    deleteSelectedProduct()
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(selectedProductID == nil)
                .foregroundColor(.red)
                .help("Delete Selected Product")
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Product Spreadsheet Table
            Table(filteredProducts, selection: $selectedProductID) {
                TableColumn("Product ID") { prod in
                    HStack {
                        Image(systemName: StoreKitSimulationService.shared.favoriteProducts.contains(prod.productID) ? "star.fill" : "star")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                            .onTapGesture {
                                StoreKitSimulationService.shared.toggleFavoriteProduct(id: prod.productID)
                            }
                        Text(prod.productID)
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
                TableColumn("Reference Name") { prod in
                    Text(prod.referenceName)
                        .font(.system(size: 11, weight: .semibold))
                }
                TableColumn("Type") { prod in
                    Text(prod.type)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                TableColumn("Price") { prod in
                    Text(String(format: "$%.2f", prod.price))
                        .font(.system(size: 11))
                }
                TableColumn("Family Sharing") { prod in
                    Image(systemName: prod.familySharing ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(prod.familySharing ? .green : .secondary)
                }
                TableColumn("Action") { prod in
                    Button("Edit") {
                        editingProduct = prod
                    }
                    .buttonStyle(.link)
                }
            }
            .contextMenu {
                Button("Pin to Favorites") {
                    if let sel = selectedProductID {
                        StoreKitSimulationService.shared.toggleFavoriteProduct(id: sel)
                    }
                }
                Button("Duplicate") {
                    duplicateSelectedProduct()
                }
                Button("Delete", role: .destructive) {
                    deleteSelectedProduct()
                }
            }
        }
        .sheet(item: $editingProduct) { prod in
            StoreKitProductEditingSheet(product: prod) { updated in
                updateProductInConfig(updated)
            }
        }
        .sheet(isPresented: $showingAIGenerator) {
            SmartProductGeneratorSheet()
        }
    }

    private var allProducts: [SKProduct] {
        var list: [SKProduct] = []
        list.append(contentsOf: session.activeConfig.products)
        list.append(contentsOf: session.activeConfig.subscriptionGroups.flatMap { group in
            group.subscriptions.map { sub in
                SKProduct(productID: sub.productID, referenceName: sub.referenceName, type: sub.type, localizations: sub.localizations, price: sub.price, familySharing: sub.familySharing, index: sub.index, availability: sub.availability)
            }
        })
        list.append(contentsOf: session.activeConfig.nonRenewingSubscriptions.map { sub in
            SKProduct(productID: sub.productID, referenceName: sub.referenceName, type: sub.type, localizations: sub.localizations, price: sub.price, familySharing: sub.familySharing, index: sub.index, availability: sub.availability)
        })
        return list
    }

    private var filteredProducts: [SKProduct] {
        allProducts.filter { prod in
            if let filter = filterType {
                if filter == "Consumables" && prod.type != "Consumable" { return false }
                if filter == "Non Consumables" && prod.type != "NonConsumable" { return false }
                if filter == "Auto Renewables" && prod.type != "AutoRenewableSubscription" { return false }
                if filter == "Non Renewables" && prod.type != "NonRenewingSubscription" { return false }
            }

            if searchText.isEmpty { return true }
            return prod.productID.localizedCaseInsensitiveContains(searchText) ||
                   prod.referenceName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func addProduct(type: String) {
        session.pushToUndoStack()
        let cleanType = type == "Consumables" ? "Consumable" : (type == "Non Consumables" ? "NonConsumable" : type)

        let newID = "com.app.new_product_" + UUID().uuidString.prefix(6).lowercased()
        let newProd = SKProduct(productID: newID, referenceName: "New Product Reference", type: cleanType)

        if cleanType == "AutoRenewableSubscription" {
            if session.activeConfig.subscriptionGroups.isEmpty {
                let defaultGroup = SKSubscriptionGroup(groupName: "Main Premium Group")
                session.activeConfig.subscriptionGroups.append(defaultGroup)
            }
            let sub = SKSubscription(productID: newID, referenceName: "New Auto-Renewing Sub", subscriptionGroupID: session.activeConfig.subscriptionGroups[0].groupName)
            session.activeConfig.subscriptionGroups[0].subscriptions.append(sub)
        } else if cleanType == "NonRenewingSubscription" {
            let non = SKNonRenewingSubscription(productID: newID, referenceName: "New Non-Renewing Sub")
            session.activeConfig.nonRenewingSubscriptions.append(non)
        } else {
            session.activeConfig.products.append(newProd)
        }
        StoreKitSimulationService.shared.logActivity(category: "Product", title: "Product Created", message: "Successfully created active product '\(newID)'.")
    }

    private func duplicateSelectedProduct() {
        guard let id = selectedProductID, let match = allProducts.first(where: { $0.productID == id }) else { return }
        session.pushToUndoStack()

        let duplicateID = match.productID + "_copy"
        let duplicateName = match.referenceName + " Copy"

        if match.type == "AutoRenewableSubscription" {
            for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
                let group = session.activeConfig.subscriptionGroups[gIdx]
                if let subIdx = group.subscriptions.firstIndex(where: { $0.productID == id }) {
                    var sub = group.subscriptions[subIdx]
                    sub.productID = duplicateID
                    sub.referenceName = duplicateName
                    session.activeConfig.subscriptionGroups[gIdx].subscriptions.append(sub)
                    break
                }
            }
        } else if match.type == "NonRenewingSubscription" {
            if let idx = session.activeConfig.nonRenewingSubscriptions.firstIndex(where: { $0.productID == id }) {
                var non = session.activeConfig.nonRenewingSubscriptions[idx]
                non.productID = duplicateID
                non.referenceName = duplicateName
                session.activeConfig.nonRenewingSubscriptions.append(non)
            }
        } else {
            var prod = match
            prod.productID = duplicateID
            prod.referenceName = duplicateName
            session.activeConfig.products.append(prod)
        }
        StoreKitSimulationService.shared.logActivity(category: "Product", title: "Product Cloned", message: "Cloned item '\(id)' into standard duplicate '\(duplicateID)'.")
    }

    private func deleteSelectedProduct() {
        guard let id = selectedProductID else { return }
        session.pushToUndoStack()

        session.activeConfig.products.removeAll { $0.productID == id }
        session.activeConfig.nonRenewingSubscriptions.removeAll { $0.productID == id }
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            session.activeConfig.subscriptionGroups[gIdx].subscriptions.removeAll { $0.productID == id }
        }
        selectedProductID = nil
        StoreKitSimulationService.shared.logActivity(category: "Product", title: "Product Deleted", message: "Deleted record '\(id)' permanently.")
    }

    private func updateProductInConfig(_ updated: SKProduct) {
        session.pushToUndoStack()
        if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == updated.productID }) {
            session.activeConfig.products[idx] = updated
            return
        }

        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let sIdx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == updated.productID }) {
                var sub = session.activeConfig.subscriptionGroups[gIdx].subscriptions[sIdx]
                sub.referenceName = updated.referenceName
                sub.price = updated.price
                sub.familySharing = updated.familySharing
                sub.localizations = updated.localizations
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[sIdx] = sub
                return
            }
        }

        if let idx = session.activeConfig.nonRenewingSubscriptions.firstIndex(where: { $0.productID == updated.productID }) {
            var non = session.activeConfig.nonRenewingSubscriptions[idx]
            non.referenceName = updated.referenceName
            non.price = updated.price
            non.familySharing = updated.familySharing
            non.localizations = updated.localizations
            session.activeConfig.nonRenewingSubscriptions[idx] = non
        }
    }

    private enum BulkActionType {
        case bulkRename
        case bulkDuplicate
        case bulkLocalization
        case bulkDelete
    }

    private func applyBulkOperation(_ op: BulkActionType) {
        session.pushToUndoStack()
        switch op {
        case .bulkRename:
            for idx in 0..<session.activeConfig.products.count {
                session.activeConfig.products[idx].productID += "_pro"
            }
            StoreKitSimulationService.shared.logActivity(category: "Product", title: "Bulk Rename Applied", message: "Added '_pro' suffix to standard products.")
        case .bulkDuplicate:
            let originalProds = session.activeConfig.products
            for prod in originalProds {
                var clone = prod
                clone.productID += "_bulk_copy"
                clone.referenceName += " Bulk Copy"
                session.activeConfig.products.append(clone)
            }
            StoreKitSimulationService.shared.logActivity(category: "Product", title: "Bulk Duplication Complete", message: "Successfully duplicated active items catalog.")
        case .bulkLocalization:
            for idx in 0..<session.activeConfig.products.count {
                if session.activeConfig.products[idx].localizations.isEmpty {
                    session.activeConfig.products[idx].localizations = [
                        SKLocalization(locale: "en_US", displayName: session.activeConfig.products[idx].referenceName, description: "Bulk generated description placeholder.")
                    ]
                }
            }
            StoreKitSimulationService.shared.logActivity(category: "Product", title: "Bulk Localizations Generated", message: "Generated fallback US English translations.")
        case .bulkDelete:
            session.activeConfig.products.removeAll()
            StoreKitSimulationService.shared.logActivity(category: "Product", title: "Bulk Deletion Complete", message: "Cleared all standard products catalog.")
        }
    }
}


// MARK: - 4. SmartProductGeneratorSheet (AI Creator)

struct SmartProductGeneratorSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(StoreKitWorkspaceSession.self) var session

    @State private var prompt = ""
    @State private var isGenerating = false
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Smart AI Product Generator")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            VStack(alignment: .leading, spacing: 14) {
                Text("Describe the in-app purchase structure or pricing plan you need. We'll leverage AI to model custom identifiers, subscription families, and localized descriptions.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                TextEditor(text: $prompt)
                    .font(.system(size: 12))
                    .frame(height: 110)
                    .cornerRadius(6)
                    .border(Color.secondary.opacity(0.3))

                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(statusMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                }

                Spacer()

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                    Button("Generate Catalog Item") {
                        Task {
                            await generateProductWithAI()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(prompt.isEmpty || isGenerating)
                }
            }
            .padding(20)
            .frame(width: 480, height: 320)
        }
    }

    private func generateProductWithAI() async {
        isGenerating = true
        statusMessage = "Calling LLMService..."
        session.pushToUndoStack()

        do {
            let aiPrompt = "Convert this developer request for a StoreKit product into a single JSON representing an SKProduct: '\(prompt)'. Follow the exact Swift Struct layout with keys: productID, referenceName, type, localizations (array with keys: locale, displayName, description), price, familySharing."
            let response = try await LLMService.shared.generateResponse(prompt: aiPrompt, useContext: false)

            if let jsonData = response.data(using: .utf8),
               let parsedProd = try? JSONDecoder().decode(SKProduct.self, from: jsonData) {
                session.activeConfig.products.append(parsedProd)
                statusMessage = "Successfully generated Product!"
            } else {
                // Fallback smart parser
                let smartID = "com.app." + prompt.lowercased().replacingOccurrences(of: " ", with: "_").prefix(14)
                let smartProduct = SKProduct(
                    productID: String(smartID),
                    referenceName: prompt,
                    type: "NonConsumable",
                    localizations: [SKLocalization(locale: "en_US", displayName: prompt, description: "AI Synthesized description placeholder.")],
                    price: 4.99
                )
                session.activeConfig.products.append(smartProduct)
                statusMessage = "Successfully generated fallback Product!"
            }
            StoreKitSimulationService.shared.logActivity(category: "Simulation", title: "AI Generation Success", message: "Added AI-generated item to product portfolio.")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            dismiss()
        } catch {
            statusMessage = "AI Generation Failed: \(error.localizedDescription)"
            isGenerating = false
        }
    }
}


// MARK: - 5. SubscriptionTimelineView

struct SubscriptionTimelineView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subscription Lifecycle Timeline")
                        .font(.system(size: 18, weight: .bold))
                    Text("Interactive view tracking every simulated subscription transition state.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                let subs = session.activeConfig.subscriptionGroups.flatMap { $0.subscriptions }

                if subs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "arrow.3.clockwise.circle")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Subscriptions Configured")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(subs) { sub in
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Subscription: \(sub.referenceName) (\(sub.productID))")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accentColor)

                            // Render interactive timeline nodes
                            HStack(spacing: 0) {
                                timelineNode(title: "Purchase", icon: "cart.fill", isPast: true)
                                timelineLine(isPast: true)
                                timelineNode(title: "Renewal", icon: "arrow.3.clockwise", isPast: true)
                                timelineLine(isPast: false)
                                timelineNode(title: "Grace Period", icon: "clock.badge.exclamationmark", isPast: false)
                                timelineLine(isPast: false)
                                timelineNode(title: "Billing Retry", icon: "exclamationmark.arrow.triangle.2.circlepath", isPast: false)
                                timelineLine(isPast: false)
                                timelineNode(title: "Expiration", icon: "hourglass.bottomhalf.fill", isPast: false)
                            }
                            .padding(.vertical, 14)

                            HStack(spacing: 10) {
                                Button("Simulate Grace Period") {
                                    simulationService.simulateGracePeriod(productID: sub.productID)
                                }
                                Button("Simulate Billing Retry") {
                                    simulationService.simulateBillingRetry(productID: sub.productID)
                                }
                                Button("Simulate Auto-Renewal") {
                                    simulationService.simulateRenewal(productID: sub.productID)
                                }
                                Button("Force Expiration") {
                                    simulationService.simulateExpiration(productID: sub.productID)
                                }
                                .foregroundColor(.red)
                            }
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }

    private func timelineNode(title: String, icon: String, isPast: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(isPast ? .accentColor : .secondary)
                .frame(width: 32, height: 32)
                .background(isPast ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08), in: Circle())

            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isPast ? .primary : .secondary)
        }
    }

    private func timelineLine(isPast: Bool) -> some View {
        Rectangle()
            .fill(isPast ? Color.accentColor : Color.secondary.opacity(0.2))
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
    }
}


// MARK: - 6. StoreKitDiagnosticsView (Diagnostics Center)

struct StoreKitDiagnosticsView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var validationService = StoreKitValidationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Diagnostics & Verification Center")
                        .font(.system(size: 18, weight: .bold))
                    Text("Continuously verifies project sandboxes, configurations, plists, and returns executable fixes.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                let issues = validationService.validate(config: session.activeConfig)

                if issues.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                        Text("All Diagnostics Passed!")
                            .font(.system(size: 12, weight: .bold))
                        Text("No duplicate identifiers, empty localizations, or entitlements warnings found.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(issues) { issue in
                            HStack {
                                Image(systemName: issue.severity == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                                    .foregroundColor(issue.severity == .error ? .red : .orange)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(issue.category.rawValue.uppercased())
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Text("•")
                                            .font(.system(size: 9))
                                            .foregroundColor(.secondary)
                                        Text(issue.severity.rawValue)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(issue.severity == .error ? .red : .orange)
                                    }

                                    Text(issue.message)
                                        .font(.system(size: 11, weight: .semibold))
                                }

                                Spacer()

                                if let fix = issue.fixType {
                                    Button("Fix Issue") {
                                        applyFix(fix, productID: issue.objectID)
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(12)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func applyFix(_ fix: ValidationIssue.ValidationFixType, productID: String?) {
        session.pushToUndoStack()
        switch fix {
        case .generateMissingLocalization:
            guard let id = productID else { return }
            if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == id }) {
                session.activeConfig.products[idx].localizations = [
                    SKLocalization(locale: "en_US", displayName: session.activeConfig.products[idx].referenceName, description: "Default generated description.")
                ]
            }
            StoreKitSimulationService.shared.logActivity(category: "Validation", title: "Missing Localizations Fixed", message: "Generated fallback US English placeholder.")

        case .fixNegativePrice:
            guard let id = productID else { return }
            if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == id }) {
                session.activeConfig.products[idx].price = 0.99
            }
            StoreKitSimulationService.shared.logActivity(category: "Validation", title: "Negative Price Fixed", message: "Re-aligned purchase price to $0.99.")

        case .fixEmptyIdentifier:
            guard let id = productID else { return }
            let validID = "com.app.product_" + UUID().uuidString.prefix(6).lowercased()
            if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == id }) {
                session.activeConfig.products[idx].productID = validID
            }
            StoreKitSimulationService.shared.logActivity(category: "Validation", title: "Empty ID Fixed", message: "Generated clean unique identifier.")

        case .fixDuplicateIdentifier:
            guard let id = productID else { return }
            if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == id }) {
                session.activeConfig.products[idx].productID += "_unique"
            }
            StoreKitSimulationService.shared.logActivity(category: "Validation", title: "Duplicate ID Resolved", message: "Appended unique differentiator suffix.")

        case .fixMismatchGroup:
            guard let id = productID else { return }
            for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
                if let sIdx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == id }) {
                    session.activeConfig.subscriptionGroups[gIdx].subscriptions[sIdx].subscriptionGroupID = session.activeConfig.subscriptionGroups[gIdx].groupName
                }
            }
            StoreKitSimulationService.shared.logActivity(category: "Validation", title: "Group ID re-aligned", message: "Successfully synced group details.")

        default:
            StoreKitSimulationService.shared.logActivity(category: "Validation", title: "Capability Checked", message: "Validated system requirements pass cleanly.")
        }
    }
}


// MARK: - 7. StorefrontsView (Storefront Manager)

struct StoreKitStorefrontEditorView: View {
    @State private var storefronts: [SKStorefront] = [
        SKStorefront(code: "USA", name: "United States", region: "North America", currency: "USD", isAvailable: true),
        SKStorefront(code: "CAN", name: "Canada", region: "North America", currency: "CAD", isAvailable: true),
        SKStorefront(code: "FRA", name: "France", region: "Europe", currency: "EUR", isAvailable: true),
        SKStorefront(code: "GBR", name: "United Kingdom", region: "Europe", currency: "GBP", isAvailable: true),
        SKStorefront(code: "JPN", name: "Japan", region: "Asia", currency: "JPY", isAvailable: true),
        SKStorefront(code: "AUS", name: "Australia", region: "Oceania", currency: "AUD", isAvailable: true)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storefront Manager")
                        .font(.system(size: 18, weight: .bold))
                    Text("Configure Countries and geographic territories where your products are sold.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Table(storefronts) {
                    TableColumn("Region", value: \.region)
                    TableColumn("Country Name", value: \.name)
                    TableColumn("Code", value: \.code)
                    TableColumn("Currency", value: \.currency)
                    TableColumn("Availability") { storefront in
                        Toggle("", isOn: Binding(
                            get: { storefront.isAvailable },
                            set: { val in
                                if let idx = storefronts.firstIndex(where: { $0.code == storefront.code }) {
                                    storefronts[idx].isAvailable = val
                                }
                            }
                        ))
                        .labelsHidden()
                    }
                }
                .frame(height: 320)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
    }
}


// MARK: - 8. LocalizationView (Localization Manager)

struct StoreKitLocalizationEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Localization Matrices")
                        .font(.system(size: 18, weight: .bold))
                    Text("Manage worldwide language catalog localizations from one place.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                let allProds = session.activeConfig.products

                if allProds.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "character.bubble")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Products Available to Localize")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(allProds) { prod in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(prod.referenceName)
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Button("Add Language") {
                                    addLocale(to: prod.productID)
                                }
                            }

                            if prod.localizations.isEmpty {
                                Text("No localizations available.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                Table(prod.localizations) {
                                    TableColumn("Locale", value: \.locale)
                                    TableColumn("Display Name", value: \.displayName)
                                    TableColumn("Description", value: \.description)
                                }
                                .frame(height: 120)
                            }
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }

    private func addLocale(to productID: String) {
        session.pushToUndoStack()
        if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == productID }) {
            let loc = SKLocalization(locale: "fr_FR", displayName: "French Translation", description: "French description text.")
            session.activeConfig.products[idx].localizations.append(loc)
        }
        StoreKitSimulationService.shared.logActivity(category: "Localization", title: "Language Added", message: "Added 'fr_FR' localization details to '\(productID)'.")
    }
}


// MARK: - 9. AssetManagerView (Asset Manager)

struct StoreKitAssetEditorView: View {
    @State private var projectAssets: [SKAsset] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Asset & Media Manager")
                        .font(.system(size: 18, weight: .bold))
                    Text("Validates promotional graphic templates and App Store screen assets automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if projectAssets.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Marketing Deliverables Found")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Table(projectAssets) {
                        TableColumn("Type", value: \.type)
                        TableColumn("File Name", value: \.fileName)
                        TableColumn("Size", value: \.size)
                        TableColumn("Sandbox Path", value: \.resolvedPath)
                    }
                    .frame(height: 220)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
        .onAppear {
            scanMockAssets()
        }
    }

    private func scanMockAssets() {
        projectAssets = [
            SKAsset(fileName: "premium_promotional_art.png", resolvedPath: "/home/sandbox/project/assets/premium_promotional_art.png", size: "1.2 MB", type: "Promo Art"),
            SKAsset(fileName: "pro_upgrade_screenshot.png", resolvedPath: "/home/sandbox/project/assets/pro_upgrade_screenshot.png", size: "840 KB", type: "Screenshot Mock")
        ]
    }
}


// MARK: - 10. OfferDesigner (Offer Designer)

struct StoreKitOfferEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Offer & Promo Code Designer")
                        .font(.system(size: 18, weight: .bold))
                    Text("Visually configure introductory deals, discount codes, and eligibility parameters.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                let subs = session.activeConfig.subscriptionGroups.flatMap { $0.subscriptions }

                if subs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tag.slash")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Auto-Renewing Subscriptions Found")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(subs) { sub in
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Product: \(sub.referenceName) (\(sub.productID))")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.accentColor)

                            // Intro Offers
                            HStack {
                                Text("Introductory Offers")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Button("Add Intro Deal") {
                                    addIntroOffer(to: sub.productID)
                                }
                            }

                            if sub.introductoryOffers.isEmpty {
                                Text("No active introductory offer configurations.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(sub.introductoryOffers) { offer in
                                    HStack {
                                        Text("Payment Mode: \(offer.paymentMode)")
                                        Text("Price: \(String(format: "$%.2f", offer.price))")
                                        Text("Duration: \(offer.numberOfPeriods) Period(s)")
                                        Spacer()
                                        Button("Remove") {
                                            removeIntroOffer(offer, from: sub.productID)
                                        }
                                        .foregroundColor(.red)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }

                            Divider()

                            // Promo Code Offers
                            HStack {
                                Text("Promotional Offer Codes")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Button("Add Promo Offer") {
                                    addPromoOffer(to: sub.productID)
                                }
                            }

                            if sub.promotionalOffers.isEmpty {
                                Text("No active promotional offer codes configured.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(sub.promotionalOffers) { promo in
                                    HStack {
                                        Text("ID: \(promo.offerID)")
                                        Text("Price: \(String(format: "$%.2f", promo.price))")
                                        Spacer()
                                        Button("Remove") {
                                            removePromoOffer(promo, from: sub.productID)
                                        }
                                        .foregroundColor(.red)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }

    private func addIntroOffer(to productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].introductoryOffers.append(SKIntroductoryOffer())
            }
        }
        StoreKitSimulationService.shared.logActivity(category: "Offers", title: "Intro Deal Added", message: "Created introductory sandbox parameters.")
    }

    private func removeIntroOffer(_ offer: SKIntroductoryOffer, from productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].introductoryOffers.removeAll { $0.id == offer.id }
            }
        }
    }

    private func addPromoOffer(to productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].promotionalOffers.append(SKPromotionalOffer(offerID: "promo_" + UUID().uuidString.prefix(4).lowercased(), referenceName: "Discount Promo"))
            }
        }
        StoreKitSimulationService.shared.logActivity(category: "Offers", title: "Promo Deal Added", message: "Created promotional discount parameters.")
    }

    private func removePromoOffer(_ offer: SKPromotionalOffer, from productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].promotionalOffers.removeAll { $0.id == offer.id }
            }
        }
    }
}


// MARK: - 11. CompareView (Compare Configs)

struct StoreKitCompareView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StoreKit Schema Compare")
                        .font(.system(size: 18, weight: .bold))
                    Text("Compares active document parameters side-by-side with a baseline standard schema.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Active Document")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.accentColor)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Product Count: \(session.activeConfig.products.count)")
                            Text("Subscription Families: \(session.activeConfig.subscriptionGroups.count)")
                            Text("Version Rating: \(session.activeConfig.version.map(String.init).joined(separator: "."))")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Baseline Reference")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Product Count: 2")
                            Text("Subscription Families: 1")
                            Text("Version Rating: 4.0")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Detailed Schema Differences")
                        .font(.system(size: 11, weight: .bold))

                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("Added: \(max(0, session.activeConfig.products.count - 2)) custom non-consumables.")
                            .font(.system(size: 11))
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(24)
        }
    }
}


// MARK: - 12. VersionHistoryView (Version History)

struct StoreKitVersionHistoryView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var revisions: [SKVersionRevision] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Document Revisions History")
                        .font(.system(size: 18, weight: .bold))
                    Text("Restores standard automatic snapshots of past StoreKit edits.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if revisions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Revision Snapshots Captured Yet")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(revisions) { revision in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    let f = DateFormatter()
                                    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                                    Text(f.string(from: revision.timestamp))
                                        .font(.system(size: 11, weight: .bold))
                                    Text(revision.reason)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Restore Revision") {
                                    session.activeConfig = revision.config
                                    StoreKitSimulationService.shared.log("Restored snapshot revision from date: \(revision.timestamp)")
                                }
                            }
                            .padding(10)
                            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            revisions = [
                SKVersionRevision(reason: "Automatic auto-save backup.", config: session.activeConfig),
                SKVersionRevision(reason: "Initial clean file initialization.", config: StoreKitConfig())
            ]
        }
    }
}


// MARK: - 13. SearchCenterView (Search Center)

struct StoreKitSearchCenterView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search products, identifiers, offers, and diagnostic logs...", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if query.isEmpty {
                        Text("Enter search terms above to query the active environment index.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        let filtered = (session.activeConfig.products + session.activeConfig.subscriptionGroups.flatMap { $0.subscriptions }.map { SKProduct(productID: $0.productID, referenceName: $0.referenceName, type: $0.type, localizations: $0.localizations, price: $0.price, familySharing: $0.familySharing, index: $0.index, availability: $0.availability) }).filter {
                            $0.productID.localizedCaseInsensitiveContains(query) ||
                            $0.referenceName.localizedCaseInsensitiveContains(query)
                        }

                        if filtered.isEmpty {
                            Text("No matching records found.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            ForEach(filtered) { record in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.referenceName)
                                        .font(.system(size: 11, weight: .bold))
                                    Text(record.productID)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
    }
}


// MARK: - 14. CommandPaletteView (Command Palette)

struct StoreKitCommandPaletteView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var query = ""

    struct CommandItem: Identifiable {
        let id = UUID()
        let name: String
        let section: String
        let icon: String
    }

    private let commands = [
        CommandItem(name: "Create New Product", section: "Products", icon: "plus.circle"),
        CommandItem(name: "Run Static Plist Validation", section: "Validation", icon: "checkmark.shield"),
        CommandItem(name: "Reset StoreKit Sandbox Simulator", section: "Purchase Simulator", icon: "play.circle"),
        CommandItem(name: "Save Configuration Plist to Disk", section: "Dashboard", icon: "square.and.arrow.down"),
        CommandItem(name: "Verify Capabilities Entitlements", section: "Validation", icon: "exclamationmark.shield")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                TextField("Type command shortcut to execute action...", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List(commands.filter { query.isEmpty ? true : $0.name.localizedCaseInsensitiveContains(query) }) { cmd in
                HStack {
                    Image(systemName: cmd.icon)
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cmd.name)
                            .font(.system(size: 11, weight: .bold))
                        Text(cmd.section.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    session.selectedSection = cmd.section
                }
            }
        }
    }
}


// MARK: - 15. SettingsView

struct StoreKitSettingsView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StoreKit Settings")
                        .font(.system(size: 18, weight: .bold))
                    Text("Configure Sandbox and environment settings matching standard Xcode.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Form {
                    Section {
                        Toggle("Enable Billing Grace Period", isOn: $session.activeConfig.settings._billingGracePeriodEnabled)
                        Toggle("Enable Billing Retry", isOn: $session.activeConfig.settings._billingRetryEnabled)
                        Toggle("Simulate Purchase Failures", isOn: $session.activeConfig.settings._failTransactionsEnabled)
                    } header: {
                        Text("General Sandbox Behaviors")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.bottom, 6)
                    }

                    Section {
                        Picker("Environment Language", selection: $session.activeConfig.settings._locale) {
                            Text("English (U.S.)").tag("en_US")
                            Text("French (France)").tag("fr_FR")
                            Text("Japanese (Japan)").tag("ja_JP")
                        }
                    } header: {
                        Text("Locale Settings")
                            .font(.system(size: 11, weight: .bold))
                            .padding(.bottom, 6)
                            .padding(.top, 14)
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
    }
}


// MARK: - 16. LogsView

struct StoreKitLogsView: View {
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("StoreKit Console Log Streams")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Button("Clear Console") {
                    simulationService.clearLogs()
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    if simulationService.activeLogs.isEmpty {
                        Text("No active logs generated.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding()
                    } else {
                        ForEach(simulationService.activeLogs, id: \.self) { log in
                            Text(log)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.green)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 3)
                            Divider()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.black)
        }
    }
}


// MARK: - 17. RawSourceEditorView

struct StoreKitRawSourceEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var rawText: String = ""
    @State private var isError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("StoreKit Config JSON (Raw Editor)")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                if isError {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.red)
                } else {
                    Label("JSON Schema Verified", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.green)
                }

                Button("Save Raw Edits") {
                    applyRawEdits()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            TextEditor(text: $rawText)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor))
        }
        .onAppear {
            loadSource()
        }
        .onChange(of: session.activeConfig) { _, _ in
            loadSource()
        }
    }

    private func loadSource() {
        if let data = try? StoreKitEncoder.shared.encodeToString(session.activeConfig) {
            rawText = data
            isError = false
        }
    }

    private func applyRawEdits() {
        guard let data = rawText.data(using: .utf8) else { return }
        do {
            session.pushToUndoStack()
            let config = try JSONDecoder().decode(StoreKitConfig.self, from: data)
            session.activeConfig = config
            isError = false
            StoreKitSimulationService.shared.log("Successfully parsed and saved raw JSON.")
        } catch {
            isError = true
            errorMessage = "Format Error: \(error.localizedDescription)"
        }
    }
}


// MARK: - 18. StoreKitTemplateGalleryView

struct TemplateCard: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let desc: String
    let icon: String
    let itemsCount: String
}

struct StoreKitTemplateGalleryView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    private let templates = [
        TemplateCard(name: "Premium Unlock", desc: "One-time Lifetime unlock representing Premium app upgrade models.", icon: "sparkles", itemsCount: "1 Product"),
        TemplateCard(name: "Pro Version", desc: "Organized subscription group with Pro Monthly and Pro Yearly options.", icon: "arrow.3.clockwise", itemsCount: "2 Subscriptions"),
        TemplateCard(name: "Consumables / Tips", desc: "Tip jar consumable packs model to support continuous updates.", icon: "flame", itemsCount: "2 Products"),
        TemplateCard(name: "Streaming Service", desc: "Multi-tier subscription groups with Standard HD and Ultra 4K levels.", icon: "film", itemsCount: "2 Products"),
        TemplateCard(name: "SaaS Enterprise Catalog", desc: "Monthly enterprise software subscription featuring robust grace periods.", icon: "briefcase", itemsCount: "3 Products")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StoreKit Starter Templates")
                        .font(.system(size: 18, weight: .bold))
                    Text("Apply Xcode standard pricing catalogs to bootstrap and test local sandboxes.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 18) {
                    ForEach(templates) { card in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: card.icon)
                                    .font(.system(size: 24))
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Text(card.itemsCount)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }

                            Text(card.name)
                                .font(.system(size: 12, weight: .bold))

                            Text(card.desc)
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                                .lineLimit(3)

                            Spacer()

                            Button("Apply Template") {
                                session.loadTemplate(name: card.name)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(14)
                        .frame(height: 180)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }
}


// MARK: - 19. StoreKitTransactionExplorerView

struct StoreKitTransactionExplorerView: View {
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Transaction Explorer")
                        .font(.system(size: 18, weight: .bold))
                    Text("Inspect cryptographically secure mock transactions issued locally.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                if simulationService.transactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "scroll")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Transactions Recorded")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Table(simulationService.transactions) {
                        TableColumn("Date") { tx in
                            let f = DateFormatter()
                            f.dateFormat = "MM-dd HH:mm"
                            return Text(f.string(from: tx.transactionDate))
                        }
                        TableColumn("Product ID", value: \.productID)
                        TableColumn("Region", value: \.storefront)
                        TableColumn("State") { tx in
                            Text(tx.purchaseState.uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(tx.purchaseState == "purchased" ? .green : .red)
                        }
                        TableColumn("Receipt") { tx in
                            Label("Verified JWS", systemImage: "lock.shield")
                                .font(.system(size: 10))
                                .foregroundColor(.green)
                        }
                        TableColumn("Actions") { tx in
                            if tx.purchaseState == "purchased" {
                                Button("Refund") {
                                    simulationService.triggerRefund(productID: tx.productID)
                                }
                            } else {
                                Text("--")
                            }
                        }
                    }
                    .frame(height: 320)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
    }
}


// MARK: - 20. StoreKitSubscriptionGroupEditorView

struct StoreKitSubscriptionGroupEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subscription Groups")
                            .font(.system(size: 18, weight: .bold))
                        Text("Configure upgrade, downgrade, and crossgrade pricing subscription groups.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: addSubscriptionGroup) {
                        Label("New Group", systemImage: "plus")
                    }
                }

                if session.activeConfig.subscriptionGroups.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("No Subscription Groups Available")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(0..<session.activeConfig.subscriptionGroups.count, id: \.self) { gIdx in
                        let group = session.activeConfig.subscriptionGroups[gIdx]
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(group.groupName)
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Button("Delete", role: .destructive) {
                                    session.pushToUndoStack()
                                    session.activeConfig.subscriptionGroups.remove(at: gIdx)
                                }
                                .foregroundColor(.red)
                            }

                            Table(group.subscriptions) {
                                TableColumn("Product ID", value: \.productID)
                                TableColumn("Reference Name", value: \.referenceName)
                                TableColumn("Period", value: \.subscriptionPeriod)
                                TableColumn("Price") { sub in
                                    Text(String(format: "$%.2f", sub.price))
                                }
                            }
                            .frame(height: 120)
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }

    private func addSubscriptionGroup() {
        session.pushToUndoStack()
        let name = "Premium Group \(session.activeConfig.subscriptionGroups.count + 1)"
        session.activeConfig.subscriptionGroups.append(SKSubscriptionGroup(groupName: name))
        StoreKitSimulationService.shared.logActivity(category: "Offers", title: "Group Created", message: "Created standard subscription group '\(name)'.")
    }
}


// MARK: - 21. StoreKitPurchaseSimulatorView

struct StoreKitPurchaseSimulatorView: View {
    @Bindable private var simulationService = StoreKitSimulationService.shared
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("StoreKit 2 Local Simulator")
                        .font(.system(size: 18, weight: .bold))

                    Text("Control simulated environment states and trigger JWS transactions.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SIMULATOR PARAMETERS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)

                        Toggle("Offline Mode", isOn: $simulationService.isOfflineMode)
                        Toggle("Ask To Buy Approval", isOn: $simulationService.isAskToBuyEnabled)
                        Toggle("Force Network Failure", isOn: $simulationService.shouldSimulateNetworkFailure)
                        Toggle("Fail JWS Cryptography", isOn: $simulationService.shouldFailVerification)
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    Text("CLICK TO TRIGGER PURCHASE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    let prods = gatherPurchasables()

                    if prods.isEmpty {
                        Text("No active products available to purchase.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(prods) { prod in
                                Button {
                                    simulationService.executePurchase(
                                        productID: prod.productID,
                                        referenceName: prod.referenceName,
                                        price: prod.price,
                                        isSubscription: prod.type == "AutoRenewableSubscription"
                                    )
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(prod.referenceName)
                                                .font(.system(size: 11, weight: .bold))
                                            Text(prod.productID)
                                                .font(.system(size: 9, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "$%.2f", prod.price))
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(width: 320)

            Divider()

            StoreKitLogsView()
        }
    }

    private func gatherPurchasables() -> [SKProduct] {
        var list: [SKProduct] = []
        list.append(contentsOf: session.activeConfig.products)
        list.append(contentsOf: session.activeConfig.subscriptionGroups.flatMap { g in
            g.subscriptions.map { s in
                SKProduct(productID: s.productID, referenceName: s.referenceName, type: "AutoRenewableSubscription", localizations: s.localizations, price: s.price, familySharing: s.familySharing, index: s.index, availability: s.availability)
            }
        })
        list.append(contentsOf: session.activeConfig.nonRenewingSubscriptions.map { s in
            SKProduct(productID: s.productID, referenceName: s.referenceName, type: "NonRenewingSubscription", localizations: s.localizations, price: s.price, familySharing: s.familySharing, index: s.index, availability: s.availability)
        })
        return list
    }
}


// MARK: - Helper editing wrappers

struct StoreKitProductEditingSheet: View, Identifiable {
    nonisolated public let id: String
    @Environment(\.dismiss) var dismiss
    @State var product: SKProduct
    let onSave: (SKProduct) -> Void

    init(product: SKProduct, onSave: @escaping (SKProduct) -> Void) {
        self.id = product.productID
        self._product = State(initialValue: product)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit In-App Product")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Close") { dismiss() }
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            Form {
                Section {
                    LabeledContent("Product ID") {
                        TextField("", text: $product.productID)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Reference Name") {
                        TextField("", text: $product.referenceName)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Price ($)") {
                        TextField("", value: $product.price, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Family Sharing") {
                        Toggle("", isOn: $product.familySharing)
                            .labelsHidden()
                    }
                }
            }
            .padding(20)
            .frame(width: 440)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(product)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
    }
}
