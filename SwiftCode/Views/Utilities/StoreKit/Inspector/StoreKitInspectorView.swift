import SwiftUI

struct StoreKitInspectorView: View {
    @Environment(StoreKitWorkspaceSession.self) var session

    // To track selected product for inspection
    @State private var selectedProductID: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("Properties Inspector")
                    .font(.headline)
                Spacer()
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    // Let user select which product they want to inspect
                    let allProducts = session.activeConfig.products +
                                      session.activeConfig.subscriptionGroups.flatMap { $0.subscriptions } +
                                      session.activeConfig.nonRenewingSubscriptions.map { SKProduct(productID: $0.productID, referenceName: $0.referenceName, type: $0.type, localizations: $0.localizations, price: $0.price, familySharing: $0.familySharing, index: $0.index, availability: $0.availability) }

                    if allProducts.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "cart.badge.questionmark")
                                .font(.largeTitle)
                                .foregroundColor(.secondary)
                            Text("No Products Available")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Add products in the workspace editor first to inspect their attributes.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 16)
                    } else {
                        // Product Picker
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Select Active Product")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Picker("", selection: $selectedProductID) {
                                Text("-- Choose Product --").tag("")
                                ForEach(allProducts, id: \.productID) { prod in
                                    Text("\(prod.referenceName) (\(prod.type))").tag(prod.productID)
                                }
                            }
                            .labelsHidden()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)

                        if selectedProductID.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle")
                                    .font(.title)
                                    .foregroundColor(.secondary)
                                Text("Select a product to view and modify properties.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                        } else if let prod = findProduct(id: selectedProductID) {
                            productInspectorBody(prod)
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            autoSelectFirstProduct()
        }
        .onChange(of: session.activeConfig) { _, _ in
            autoSelectFirstProduct()
        }
    }

    private func autoSelectFirstProduct() {
        if selectedProductID.isEmpty {
            if let first = session.activeConfig.products.first {
                selectedProductID = first.productID
            } else if let firstSub = session.activeConfig.subscriptionGroups.first?.subscriptions.first {
                selectedProductID = firstSub.productID
            } else if let firstNon = session.activeConfig.nonRenewingSubscriptions.first {
                selectedProductID = firstNon.productID
            }
        }
    }

    private func findProduct(id: String) -> SKProduct? {
        if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == id }) {
            return session.activeConfig.products[idx]
        }
        for group in session.activeConfig.subscriptionGroups {
            if let idx = group.subscriptions.firstIndex(where: { $0.productID == id }) {
                let sub = group.subscriptions[idx]
                return SKProduct(productID: sub.productID, referenceName: sub.referenceName, type: sub.type, localizations: sub.localizations, price: sub.price, familySharing: sub.familySharing, index: sub.index, availability: sub.availability)
            }
        }
        if let idx = session.activeConfig.nonRenewingSubscriptions.firstIndex(where: { $0.productID == id }) {
            let non = session.activeConfig.nonRenewingSubscriptions[idx]
            return SKProduct(productID: non.productID, referenceName: non.referenceName, type: non.type, localizations: non.localizations, price: non.price, familySharing: non.familySharing, index: non.index, availability: non.availability)
        }
        return nil
    }

    private func updateProductOnWorkspace(_ updated: SKProduct) {
        session.pushToUndoStack()

        if let idx = session.activeConfig.products.firstIndex(where: { $0.productID == updated.productID }) {
            session.activeConfig.products[idx] = updated
            return
        }

        for gIdx in 0..<session.activeConfig.subscriptionGroups.count {
            let group = session.activeConfig.subscriptionGroups[gIdx]
            if let sIdx = group.subscriptions.firstIndex(where: { $0.productID == updated.productID }) {
                var sub = group.subscriptions[sIdx]
                sub.referenceName = updated.referenceName
                sub.price = updated.price
                sub.familySharing = updated.familySharing
                sub.availability = updated.availability
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
            non.availability = updated.availability
            non.localizations = updated.localizations
            session.activeConfig.nonRenewingSubscriptions[idx] = non
            return
        }
    }

    @ViewBuilder
    private func productInspectorBody(_ product: SKProduct) -> some View {
        var bindingProduct = Binding<SKProduct>(
            get: { product },
            set: { updateProductOnWorkspace($0) }
        )

        VStack(alignment: .leading, spacing: 14) {
            // Section: Meta Identity
            VStack(alignment: .leading, spacing: 6) {
                Text("PRODUCT IDENTITY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text("Type")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(product.type)
                            .font(.subheadline.bold())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Product Identifier")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. com.app.premium", text: bindingProduct.productID)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reference Name")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. Premium Pro", text: bindingProduct.referenceName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 14)

            // Section: Pricing & Availability
            VStack(alignment: .leading, spacing: 6) {
                Text("PRICING & PROMOTION")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                VStack(spacing: 8) {
                    HStack {
                        Text("Price")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("", value: bindingProduct.price, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }

                    Toggle("Family Sharing Enabled", isOn: bindingProduct.familySharing)
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Picker("Availability", selection: bindingProduct.availability) {
                        Text("All Regions").tag("all")
                        Text("Remove From Sale").tag("none")
                    }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 14)

            // Section: App Store Review Info
            VStack(alignment: .leading, spacing: 6) {
                Text("APP STORE REVIEW METADATA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Review Notes")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextEditor(text: .constant("This unlock gives lifetime access. Please purchase to verify view controllers are unlocked correctly."))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 70)
                        .cornerRadius(6)
                        .border(Color.secondary.opacity(0.3))

                    Text("Mock Images & Screenshots")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)

                    HStack {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                        Text("promotion_banner.png")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(6)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 14)
        }
    }
}
