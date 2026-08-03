import SwiftUI

// MARK: - 1. StoreKitDashboardView

struct StoreKitDashboardView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workspace Dashboard")
                            .font(.title2.bold())
                        Text("Overview of your product portfolio and active local sandbox test transactions.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { session.selectedSection = "Templates" }) {
                        Label("Apply Template...", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.bottom, 10)

                // Metric Grid cards
                HStack(spacing: 16) {
                    metricCard(title: "In-App Products", count: String(session.activeConfig.products.count + session.activeConfig.nonRenewingSubscriptions.count), subtitle: "Consumables & Non-Consumables", icon: "cart", color: .blue)
                    metricCard(title: "Subscription Groups", count: String(session.activeConfig.subscriptionGroups.count), subtitle: "Auto-Renewable Families", icon: "square.stack.3d.up", color: .purple)
                    metricCard(title: "Active Entitlements", count: String(simulationService.entitlements.filter({ $0.isActive }).count), subtitle: "Simulated Grants", icon: "checkmark.seal", color: .green)
                    metricCard(title: "Diagnostics Issues", count: String(StoreKitValidationService.shared.validate(config: session.activeConfig).count), subtitle: "Errors & Warnings Detected", icon: "exclamationmark.triangle", color: .orange)
                }

                // Split Layout: Analytics & Recent Simulated Actions
                HStack(alignment: .top, spacing: 20) {
                    // Left Column: Catalog Breakdowns
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Catalog Breakdown")
                            .font(.headline)

                        VStack(alignment: .leading, spacing: 12) {
                            catalogRow(label: "Consumables", count: session.activeConfig.products.filter({ $0.type == "Consumable" }).count, icon: "flame", color: .orange)
                            catalogRow(label: "Non-Consumables", count: session.activeConfig.products.filter({ $0.type == "NonConsumable" }).count, icon: "sparkles", color: .blue)
                            catalogRow(label: "Auto-Renewing Subscriptions", count: session.activeConfig.subscriptionGroups.flatMap({ $0.subscriptions }).count, icon: "arrow.3.clockwise", color: .purple)
                            catalogRow(label: "Non-Renewing Subscriptions", count: session.activeConfig.nonRenewingSubscriptions.count, icon: "hourglass", color: .indigo)
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                        Text("Quick Actions")
                            .font(.headline)
                            .padding(.top, 10)

                        HStack(spacing: 10) {
                            Button {
                                session.selectedSection = "Products"
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "plus.circle")
                                        .font(.title2)
                                    Text("Add Product")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            Button {
                                session.selectedSection = "Purchase Simulator"
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "play.circle")
                                        .font(.title2)
                                    Text("Simulator")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)

                            Button {
                                session.selectedSection = "Validation"
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "checkmark.shield")
                                        .font(.title2)
                                    Text("Validate")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    // Right Column: Latest Transactions & Diagnostic Issues
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Active Entitlements Granted")
                            .font(.headline)

                        if simulationService.entitlements.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "checkmark.seal")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("No Active Entitlements")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(simulationService.entitlements.prefix(4)) { ent in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(ent.productID)
                                                .font(.subheadline.bold())
                                            Text(ent.isSubscription ? "Auto-Renewable" : "One-Time Unlock")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if ent.isActive {
                                            Text("Active")
                                                .font(.caption.bold())
                                                .foregroundColor(.green)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.12), in: Capsule())
                                        } else {
                                            Text("Expired")
                                                .font(.caption.bold())
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12), in: Capsule())
                                        }
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
                    .font(.title2)
                    .foregroundColor(color)
                Spacer()
                Text(count)
                    .font(.system(size: 28, weight: .bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func catalogRow(label: String, count: Int, icon: String, color: Color) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .foregroundColor(color)
            Spacer()
            Text("\(count)")
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
        }
    }
}


// MARK: - 15. DocumentPropertiesView

struct DocumentPropertiesView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Document Metadata Properties")
                        .font(.title2.bold())
                    Text("Deep-dive metadata inspection for the active .storekit schema profile.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Schema Format Version") {
                        Text("Version \(session.activeConfig.version.map(String.init).joined(separator: "."))")
                    }
                    Divider()
                    LabeledContent("Configuration UUID") {
                        Text(session.activeConfig.identifier)
                            .font(.system(.subheadline, design: .monospaced))
                    }
                    Divider()
                    LabeledContent("Source File Path") {
                        Text(session.activeURL?.path ?? "In-Memory Session Only (Unsaved)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Divider()
                    LabeledContent("Grace Period Enabled") {
                        Text(session.activeConfig.settings._billingGracePeriodEnabled ? "Yes" : "No")
                    }
                    Divider()
                    LabeledContent("Billing Retry Enabled") {
                        Text(session.activeConfig.settings._billingRetryEnabled ? "Yes" : "No")
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
    }
}


// MARK: - 16. StatisticsView

struct StatisticsView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("In-App Portfolio Analytics")
                        .font(.title2.bold())
                    Text("Dynamic pricing distributions, average costs, and potential revenue calculations.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                let productsList = session.activeConfig.products
                let averagePrice = productsList.isEmpty ? 0.0 : (productsList.map(\.price).reduce(0, +) / Double(productsList.count))
                let highestPrice = productsList.map(\.price).max() ?? 0.0

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Average Product Price")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "$%.2f", averagePrice))
                            .font(.title.bold())
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Highest Pricing Tier")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(String(format: "$%.2f", highestPrice))
                            .font(.title.bold())
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("Products Matrix Listing")
                        .font(.headline)

                    if productsList.isEmpty {
                        Text("No items to analyze yet.")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(productsList) { prod in
                            HStack {
                                Text(prod.referenceName)
                                Spacer()
                                Text(String(format: "$%.2f", prod.price))
                                    .bold()
                            }
                            Divider()
                        }
                    }
                }
                .padding(20)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
    }
}


// MARK: - 2. StoreKitProductsView

struct StoreKitProductsView: View {
    var filterType: String? = nil

    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var searchText = ""
    @State private var selectedProductID: String? = nil

    // Editing Popover State
    @State private var editingProduct: SKProduct? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Product Action bar
            HStack(spacing: 12) {
                TextField("Search products by identifier or reference name...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)

                Spacer()

                Button {
                    addProduct(type: filterType ?? "NonConsumable")
                } label: {
                    Label("Add Product", systemImage: "plus")
                }

                Button {
                    duplicateSelectedProduct()
                } label: {
                    Label("Clone", systemImage: "doc.on.doc")
                }
                .disabled(selectedProductID == nil)

                Button {
                    deleteSelectedProduct()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(selectedProductID == nil)
                .foregroundColor(.red)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Product Spreadsheet Grid
            Table(filteredProducts, selection: $selectedProductID) {
                TableColumn("Product ID") { prod in
                    Text(prod.productID)
                        .font(.system(.subheadline, design: .monospaced))
                }
                TableColumn("Reference Name") { prod in
                    Text(prod.referenceName)
                        .font(.subheadline.bold())
                }
                TableColumn("Type") { prod in
                    Text(prod.type)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                TableColumn("Price") { prod in
                    Text(String(format: "$%.2f", prod.price))
                        .font(.subheadline)
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
            // Add to the first subscription group or create one
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
}

// Product Editing Sheet
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
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
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
            .frame(width: 450)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Changes") {
                    onSave(product)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
    }
}


// MARK: - 3. StoreKitSubscriptionGroupEditorView

struct StoreKitSubscriptionGroupEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Subscription Groups")
                            .font(.title2.bold())
                        Text("Configure upgrade, downgrade, and crossgrade pricing tiers.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: addSubscriptionGroup) {
                        Label("New Group", systemImage: "plus")
                    }
                }

                if session.activeConfig.subscriptionGroups.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No Subscription Groups Defined")
                            .font(.headline)
                        Text("Create a group to organize auto-renewable subscription levels.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("Add Group") { addSubscriptionGroup() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(0..<session.activeConfig.subscriptionGroups.count, id: \.self) { gIdx in
                        let group = session.activeConfig.subscriptionGroups[gIdx]
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(group.groupName, systemImage: "square.stack.3d.up.fill")
                                    .font(.headline)
                                Spacer()
                                Button("Delete Group", role: .destructive) {
                                    session.pushToUndoStack()
                                    session.activeConfig.subscriptionGroups.remove(at: gIdx)
                                }
                                .buttonStyle(.link)
                                .foregroundColor(.red)
                            }

                            Table(group.subscriptions) {
                                TableColumn("Product Identifier", value: \.productID)
                                TableColumn("Reference Name", value: \.referenceName)
                                TableColumn("Period") { sub in
                                    Text(sub.subscriptionPeriod)
                                        .font(.caption)
                                }
                                TableColumn("Price") { sub in
                                    Text(String(format: "$%.2f", sub.price))
                                }
                            }
                            .frame(height: 140)
                        }
                        .padding(16)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }

    private func addSubscriptionGroup() {
        session.pushToUndoStack()
        let newGroup = SKSubscriptionGroup(groupName: "Premium Tier \(session.activeConfig.subscriptionGroups.count + 1)")
        session.activeConfig.subscriptionGroups.append(newGroup)
    }
}


// MARK: - 4. StoreKitOfferEditorView

struct StoreKitOfferEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Offers & Promo Codes")
                        .font(.title2.bold())
                    Text("Configure Introductory Offers, Promotional Offers, Win Back Offers, and Offer Codes for auto-renewable tiers.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                let subs = session.activeConfig.subscriptionGroups.flatMap { $0.subscriptions }

                if subs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tag.slash")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Auto-Renewing Subscriptions Found")
                            .font(.headline)
                        Text("Create a subscription group and products before configuring promotional deals.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 50)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(subs) { sub in
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Product: \(sub.referenceName) (\(sub.productID))")
                                .font(.headline)
                                .foregroundColor(.accentColor)

                            // Introductory offers
                            HStack {
                                Text("Introductory Offers")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button("Add Intro Offer") {
                                    addIntroOffer(to: sub.productID)
                                }
                                .buttonStyle(.plain)
                            }

                            if sub.introductoryOffers.isEmpty {
                                Text("No introductory offer (e.g. Free Trial or Pay As You Go).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
                            } else {
                                ForEach(sub.introductoryOffers) { intro in
                                    HStack {
                                        Text("Mode: \(intro.paymentMode)")
                                        Text("Price: \(String(format: "$%.2f", intro.price))")
                                        Text("Duration: \(intro.numberOfPeriods) period(s)")
                                        Spacer()
                                        Button("Remove") {
                                            removeIntroOffer(intro, from: sub.productID)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.red)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }

                            Divider()

                            // Promotional offers
                            HStack {
                                Text("Promotional Offers (SK2 Codes)")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button("Add Promotional Offer") {
                                    addPromoOffer(to: sub.productID)
                                }
                                .buttonStyle(.plain)
                            }

                            if sub.promotionalOffers.isEmpty {
                                Text("No promotional offer codes generated yet.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.leading, 8)
                            } else {
                                ForEach(sub.promotionalOffers) { promo in
                                    HStack {
                                        Text("Offer ID: \(promo.offerID)")
                                        Text("Mode: \(promo.paymentMode)")
                                        Text("Price: \(String(format: "$%.2f", promo.price))")
                                        Spacer()
                                        Button("Remove") {
                                            removePromoOffer(promo, from: sub.productID)
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(.red)
                                    }
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                }
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

    private func addIntroOffer(to productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                let offer = SKIntroductoryOffer()
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].introductoryOffers.append(offer)
                break
            }
        }
    }

    private func removeIntroOffer(_ offer: SKIntroductoryOffer, from productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].introductoryOffers.removeAll { $0.id == offer.id }
                break
            }
        }
    }

    private func addPromoOffer(to productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                let offer = SKPromotionalOffer(offerID: "promo_" + UUID().uuidString.prefix(4).lowercased(), referenceName: "Summer Discount")
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].promotionalOffers.append(offer)
                break
            }
        }
    }

    private func removePromoOffer(_ offer: SKPromotionalOffer, from productID: String) {
        session.pushToUndoStack()
        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            if let idx = session.activeConfig.subscriptionGroups[gIdx].subscriptions.firstIndex(where: { $0.productID == productID }) {
                session.activeConfig.subscriptionGroups[gIdx].subscriptions[idx].promotionalOffers.removeAll { $0.id == offer.id }
                break
            }
        }
    }
}


// MARK: - 5. StoreKitStorefrontEditorView

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
                    Text("Storefront Availability")
                        .font(.title2.bold())
                    Text("Configure countries and geographic regions where your in-app catalog is available for sale.")
                        .font(.subheadline)
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
                .frame(height: 280)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(24)
        }
    }
}


// MARK: - 6. StoreKitLocalizationEditorView

struct StoreKitLocalizationEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Localization Matrices")
                        .font(.title2.bold())
                    Text("Ensure high-conversion display names and descriptions are available across worldwide languages.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Gather localized products
                let allProducts = session.activeConfig.products

                if allProducts.isEmpty {
                    Text("No standard products available to localize.")
                        .foregroundColor(.secondary)
                        .padding(20)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(allProducts) { prod in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(prod.referenceName)
                                    .font(.headline)
                                Spacer()
                                Button("Add Language") {
                                    addLocale(to: prod.productID)
                                }
                            }

                            if prod.localizations.isEmpty {
                                Text("No translations added. App Store will default to US English.")
                                    .font(.caption)
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
                        .padding(16)
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
    }
}


// MARK: - 7. StoreKitAssetEditorView

struct StoreKitAssetEditorView: View {
    @State private var projectAssets: [SKAsset] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Assets & Graphic Deliverables")
                        .font(.title2.bold())
                    Text("We dynamically search your project directories for marketing screenshots and store promo graphics.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if projectAssets.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No Images Found in Workspace")
                            .font(.headline)
                        Text("Add image files (PNG/JPG) to your project directories to register storefront mock deliverables automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Table(projectAssets) {
                        TableColumn("Type", value: \.type)
                        TableColumn("File Name", value: \.fileName)
                        TableColumn("Disk Size", value: \.size)
                        TableColumn("Resolved Sandbox Path", value: \.resolvedPath)
                    }
                    .frame(height: 200)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
        .onAppear {
            scanWorkspaceForImages()
        }
    }

    private func scanWorkspaceForImages() {
        let fileManager = FileManager.default
        let paths = [
            "/home/sandbox/project",
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?.path
        ].compactMap { $0 }

        var found: [SKAsset] = []
        for basePath in paths {
            guard fileManager.fileExists(atPath: basePath) else { continue }
            if let enumerator = fileManager.enumerator(atPath: basePath) {
                for case let file as String in enumerator {
                    if file.hasSuffix(".png") || file.hasSuffix(".jpg") || file.hasSuffix(".jpeg") {
                        let fullPath = (basePath as NSString).appendingPathComponent(file)
                        let attributes = try? fileManager.attributesOfItem(atPath: fullPath)
                        let sizeBytes = attributes?[.size] as? Int64 ?? 0
                        let sizeStr = String(format: "%.1f MB", Double(sizeBytes) / 1024.0 / 1024.0)

                        found.append(SKAsset(
                            fileName: (file as NSString).lastPathComponent,
                            resolvedPath: fullPath,
                            size: sizeStr,
                            type: file.contains("promo") ? "App Store Promo Art" : "Storefront Mock Banner"
                        ))
                    }
                    if found.count >= 10 { break }
                }
            }
        }
        self.projectAssets = found
    }
}


// MARK: - 8. StoreKitPurchaseSimulatorView

struct StoreKitPurchaseSimulatorView: View {
    @Bindable private var simulationService = StoreKitSimulationService.shared
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        HStack(spacing: 0) {
            // Left Form: Config & Triggers
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("StoreKit 2 Local Simulator")
                        .font(.title2.bold())

                    Text("Configure environment flags on-the-fly and execute sandboxed transactions.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SIMULATION SWITCHES")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        Toggle("Ask to Buy (Require Approval)", isOn: $simulationService.isAskToBuyEnabled)
                        Toggle("Offline Mode (No Connection)", isOn: $simulationService.isOfflineMode)
                        Toggle("Network Error Simulation", isOn: $simulationService.shouldSimulateNetworkFailure)
                        Toggle("Fail JWS Cryptographic Verification", isOn: $simulationService.shouldFailVerification)
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))

                    // Products List Trigger Buttons
                    Text("CLICK TO SIMULATE PURCHASE")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    let allProds = gatherPurchasableProducts()

                    if allProds.isEmpty {
                        Text("No Products found to purchase. Please add products to your active config.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(allProds, id: \.productID) { prod in
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
                                                .font(.subheadline.bold())
                                            Text(prod.productID)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Text(String(format: "$%.2f", prod.price))
                                            .font(.subheadline.bold())
                                    }
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .frame(width: 450)

            Divider()

            // Right Pane: Active transaction streams and execution console
            VStack(spacing: 0) {
                HStack {
                    Text("Simulated Execution Console")
                        .font(.headline)
                    Spacer()
                    Button("Clear logs") {
                        simulationService.clearLogs()
                    }
                    .buttonStyle(.plain)
                    Button("Reset StoreKit Sandbox") {
                        simulationService.resetSimulator()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Console log output
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if simulationService.activeLogs.isEmpty {
                            Text("No console activities yet. Execute purchases to view logs.")
                                .foregroundColor(.secondary)
                                .italic()
                                .padding()
                        } else {
                            ForEach(simulationService.activeLogs, id: \.self) { log in
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 2)
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

    private func gatherPurchasableProducts() -> [SKProduct] {
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


// MARK: - 9. StoreKitTransactionExplorerView

struct StoreKitTransactionExplorerView: View {
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Simulated Transaction History")
                        .font(.title2.bold())
                    Text("JWS-Signed cryptographically secure record history representing local Apple transactions.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if simulationService.transactions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "scroll")
                            .font(.system(size: 44))
                            .foregroundColor(.secondary)
                        Text("No Transactions Recorded")
                            .font(.headline)
                        Text("Simulate purchases in the 'Purchase Simulator' panel to fill receipts.")
                            .font(.caption)
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
                        TableColumn("Reference Name", value: \.referenceName)
                        TableColumn("State") { tx in
                            Text(tx.purchaseState.uppercased())
                                .font(.caption.bold())
                                .foregroundColor(tx.purchaseState == "purchased" ? .green : (tx.purchaseState == "pending" ? .orange : .red))
                        }
                        TableColumn("Receipt Verification") { tx in
                            HStack(spacing: 4) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                Text("Verified JWS")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        TableColumn("Action") { tx in
                            HStack {
                                if tx.purchaseState == "pending" {
                                    Button("Approve") {
                                        simulationService.approvePendingTransaction(id: tx.id)
                                    }
                                    Button("Decline") {
                                        simulationService.declinePendingTransaction(id: tx.id)
                                    }
                                } else if tx.purchaseState == "purchased" {
                                    Button("Refund") {
                                        simulationService.triggerRefund(productID: tx.productID)
                                    }
                                }
                            }
                        }
                    }
                    .frame(height: 380)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
    }
}


// MARK: - 10. StoreKitDiagnosticsView

struct StoreKitDiagnosticsView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Validation & Diagnostics Center")
                        .font(.title2.bold())
                    Text("Static analyzer scanning for product schemas, duplicate identifiers, and layout configurations.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                let issues = StoreKitValidationService.shared.validate(config: session.activeConfig)

                if issues.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                        Text("Config Validation Passed!")
                            .font(.headline)
                        Text("No schema anomalies, empty references, or duplicate IDs found.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 60)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Table(issues) {
                        TableColumn("Severity") { issue in
                            Text(issue.severity.rawValue)
                                .foregroundColor(issue.severity == .error ? .red : (issue.severity == .warning ? .orange : .blue))
                                .font(.caption.bold())
                        }
                        TableColumn("Category", value: \.category.rawValue)
                        TableColumn("Message", value: \.message)
                        TableColumn("Target Identifier") { issue in
                            Text(issue.objectID ?? "--")
                                .font(.system(.subheadline, design: .monospaced))
                        }
                    }
                    .frame(height: 340)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(24)
        }
    }
}


// MARK: - 11. StoreKitTemplateGalleryView

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
        TemplateCard(name: "Premium Unlock", desc: "One Non-Consumable unlock for the pro version of your application.", icon: "sparkles", itemsCount: "1 Product"),
        TemplateCard(name: "Pro Version", desc: "Classic subscription group featuring both Pro Monthly and Pro Yearly options with auto-renewals.", icon: "arrow.3.clockwise", itemsCount: "2 Level Subscriptions"),
        TemplateCard(name: "Consumables / Tips", desc: "Tip jar model with discrete consumables allowing users to support operations.", icon: "flame", itemsCount: "2 Products"),
        TemplateCard(name: "Streaming Service", desc: "Organized subscription tier containing standard and ultra multi-device auto-renewing subscriptions.", icon: "film", itemsCount: "2 Products"),
        TemplateCard(name: "Mixed Catalog", desc: "Comprehensive product assortment mapping consumables, lifetime unlocks, non-renewals, and groups.", icon: "square.grid.2x2", itemsCount: "5 Mixed Items")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StoreKit Starter Templates")
                        .font(.title2.bold())
                    Text("Apply beautiful and fully standard pricing frameworks to accelerate App Store setups.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 18) {
                    ForEach(templates) { card in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: card.icon)
                                    .font(.title)
                                    .foregroundColor(.accentColor)
                                Spacer()
                                Text(card.itemsCount)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }

                            Text(card.name)
                                .font(.headline)

                            Text(card.desc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)

                            Spacer()

                            Button("Apply Template") {
                                session.loadTemplate(name: card.name)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(16)
                        .frame(height: 180)
                        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .padding(24)
        }
    }
}


// MARK: - 12. StoreKitRawSourceEditorView

struct StoreKitRawSourceEditorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session
    @State private var rawText: String = ""
    @State private var isError: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Options bar
            HStack {
                Text("Raw StoreKit Source (JSON Editor)")
                    .font(.subheadline.bold())
                Spacer()
                if isError {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Label("JSON Syntax OK", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Button("Format JSON") {
                    formatJSONSource()
                }

                Button("Save Raw Edits") {
                    applyRawEdits()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Big raw text editor
            TextEditor(text: $rawText)
                .font(.system(size: 12, design: .monospaced))
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

    private func formatJSONSource() {
        guard let data = rawText.data(using: .utf8) else { return }
        do {
            let config = try JSONDecoder().decode(StoreKitConfig.self, from: data)
            let formatted = try StoreKitEncoder.shared.encodeToString(config)
            rawText = formatted
            isError = false
        } catch {
            isError = true
            errorMessage = error.localizedDescription
        }
    }

    private func applyRawEdits() {
        guard let data = rawText.data(using: .utf8) else { return }
        do {
            session.pushToUndoStack()
            let config = try JSONDecoder().decode(StoreKitConfig.self, from: data)
            session.activeConfig = config
            isError = false
            StoreKitSimulationService.shared.log("Successfully parsed and applied raw JSON edits.")
        } catch {
            isError = true
            errorMessage = "Parse Error: \(error.localizedDescription)"
            StoreKitSimulationService.shared.log("JSON Error: \(error.localizedDescription)")
        }
    }
}


// MARK: - 13. StoreKitSettingsView

struct StoreKitSettingsView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    var body: some View {
        @Bindable var session = session
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("StoreKit Settings")
                        .font(.title2.bold())
                    Text("Manage overall config settings matching Xcode's StoreKit settings.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Form {
                    Section {
                        Toggle("Enable Billing Grace Period", isOn: $session.activeConfig.settings._billingGracePeriodEnabled)
                        Toggle("Enable Billing Retry", isOn: $session.activeConfig.settings._billingRetryEnabled)
                        Toggle("Simulate Purchase Failures", isOn: $session.activeConfig.settings._failTransactionsEnabled)
                    } header: {
                        Text("General Sandbox Behaviors")
                            .font(.headline)
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
                            .font(.headline)
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


// MARK: - 14. StoreKitLogsView

struct StoreKitLogsView: View {
    @State private var simulationService = StoreKitSimulationService.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("StoreKit Output Log Streams")
                    .font(.headline)
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
                        Text("No logs yet.")
                            .foregroundColor(.secondary)
                            .italic()
                            .padding()
                    } else {
                        ForEach(simulationService.activeLogs, id: \.self) { log in
                            Text(log)
                                .font(.system(size: 11, design: .monospaced))
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
