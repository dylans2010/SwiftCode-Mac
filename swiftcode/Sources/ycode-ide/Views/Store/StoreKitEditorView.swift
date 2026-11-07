import Foundation
import StoreKitConfiguration
import SwiftUI
import YcodeIDECore
import YcodeIDEShell

struct StoreKitEditorView: View {
    @Bindable var model: StoreKitEditorModel
    @Environment(\.colorScheme) private var scheme
    @State private var rawText = ""
    @State private var showingRaw = false
    @State private var compareSnapshot: StoreKitSnapshot?
    @State private var command = ""

    var body: some View {
        let c = ShellColors(scheme)
        HStack(spacing: 0) {
            sidebar(c)
                .frame(width: 210)
                .background(c.sidebar)
            Hairline(color: c.sidebarDivider, vertical: true)
            content(c)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(c.content)
        }
        .shellTarget("storekit editor")
    }

    private func sidebar(_ c: ShellColors) -> some View {
        List(selection: Binding<StoreKitEditorSection?>(get: { model.selectedSection }, set: { if let s = $0 { model.selectedSection = s } })) {
            ForEach(groupedSections, id: \.0) { group, sections in
                Section(group) {
                    ForEach(sections) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }
            if !model.simulation.favoriteProducts.isEmpty {
                Section("Favorites") {
                    ForEach(Array(model.simulation.favoriteProducts).sorted(), id: \.self) { id in
                        Label(id, systemImage: "star.fill")
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var groupedSections: [(String, [StoreKitEditorSection])] {
        var order: [String] = []
        var map: [String: [StoreKitEditorSection]] = [:]
        for section in StoreKitEditorSection.allCases {
            if map[section.group] == nil { order.append(section.group) }
            map[section.group, default: []].append(section)
        }
        return order.map { ($0, map[$0]!) }
    }

    @ViewBuilder
    private func content(_ c: ShellColors) -> some View {
        VStack(spacing: 0) {
            if let p = model.problem { ProblemBanner(message: p) { model.clearProblem() } }
            if model.isReadOnly {
                ProblemBanner(message: "This configuration was synchronized with App Store Connect and is read-only.") {}
            }
            switch model.selectedSection {
            case .dashboard: dashboard(c)
            case .products, .consumables, .nonConsumables, .autoRenewables, .nonRenewables, .explorer:
                productList(c)
            case .groups: groupList(c)
            case .offers: offerList(c)
            case .storefronts, .settings: settingsForm(c)
            case .validation: validationList(c)
            case .simulator: simulatorView(c)
            case .transactions: transactionList(c)
            case .templates: templateList(c)
            case .history: historyList(c)
            case .compare: compareView(c)
            case .localization: localizationList(c)
            case .timeline: timelineList(c)
            case .search: searchView(c)
            case .commandPalette: commandPalette(c)
            case .logs: logsView(c)
            case .rawSource: rawSourceView(c)
            case .assets: assetsNote(c)
            }
        }
    }

    private func dashboard(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Health \(model.healthScore) / 100")
                    .font(.title2)
                Text("\(model.allProducts.count) products · \(model.configuration.subscriptionGroups?.count ?? 0) subscription groups · \(model.errors.count) errors · \(model.warnings.count) warnings")
                    .foregroundStyle(c.secondaryLabel)
                if let id = model.configuration.identifier {
                    Text("Identifier \(id)")
                        .font(.caption)
                        .foregroundStyle(c.secondaryLabel)
                }
                Divider()
                Text("Validation").font(.headline)
                ForEach(model.validationIssues().prefix(10)) { issue in
                    HStack {
                        Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? c.error : c.warning)
                        Text(issue.message).font(.callout)
                    }
                }
                if model.validationIssues().isEmpty {
                    Text("All diagnostics passed.").foregroundStyle(c.secondaryLabel)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func productList(_ c: ShellColors) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search products", text: $model.searchText)
                        .textFieldStyle(.roundedBorder)
                    Menu("Add") {
                        Button("Consumable") { model.addProduct(kind: .consumable) }
                        Button("Non-Consumable") { model.addProduct(kind: .nonConsumable) }
                        Button("Non-Renewing Subscription") { model.addProduct(kind: .nonRenewingSubscription) }
                    }
                }
                .padding(8)
                List(model.products(in: model.selectedSection), id: \.location) { loc, product in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(product.referenceName ?? product.productID ?? "Product")
                            Text("\(product.productID ?? "") · \(product.displayPrice ?? "")")
                                .font(.caption)
                                .foregroundStyle(c.secondaryLabel)
                        }
                        Spacer()
                        Button { model.simulation.toggleFavoriteProduct(id: product.productID ?? "") } label: {
                            Image(systemName: model.simulation.favoriteProducts.contains(product.productID ?? "") ? "star.fill" : "star")
                        }
                        .buttonStyle(.plain)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedProductID = product.productID }
                    .contextMenu {
                        Button("Duplicate") { _ = model.duplicateProduct(at: loc) }
                        Button("Delete", role: .destructive) { model.removeProduct(at: loc) }
                    }
                }
            }
            .frame(width: 320)
            Hairline(color: c.separator, vertical: true)
            inspector(c)
                .frame(maxWidth: .infinity)
        }
    }

    private func updateSelected(_ edit: (inout ConfiguredProduct) -> Void) {
        guard let id = model.selectedProductID,
              let loc = model.allProducts.first(where: { $0.product.productID == id })?.location,
              var product = model.product(at: loc) else { return }
        edit(&product)
        model.setProduct(product, at: loc)
    }

    private func inspector(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let id = model.selectedProductID,
                   let loc = model.allProducts.first(where: { $0.product.productID == id })?.location,
                   let product = model.product(at: loc) {
                    Text(product.referenceName ?? product.productID ?? "Product").font(.headline)
                    LabeledField(label: "Product ID", text: product.productID ?? "") { text in updateSelected { $0.productID = text } }
                    LabeledField(label: "Reference Name", text: product.referenceName ?? "") { text in updateSelected { $0.referenceName = text } }
                    LabeledField(label: "Display Price", text: product.displayPrice ?? "") { text in updateSelected { $0.displayPrice = text } }
                    Picker("Type", selection: Binding(
                        get: { product.type?.rawValue ?? "NonConsumable" },
                        set: { newValue in updateSelected { $0.type = ProductKind(rawValue: newValue) } }
                    )) {
                        ForEach(["Consumable", "NonConsumable", "NonRenewingSubscription", "RecurringSubscription"], id: \.self) { kind in
                            Text(kind).tag(kind)
                        }
                    }
                    Toggle("Family Shareable", isOn: Binding(
                        get: { product.familyShareable ?? false },
                        set: { newValue in updateSelected { $0.familyShareable = newValue } }
                    ))
                    if product.type == .recurringSubscription {
                        LabeledField(label: "Renewal Period", text: product.recurringSubscriptionPeriod ?? "") { text in updateSelected { $0.recurringSubscriptionPeriod = text } }
                        Text("Standard periods: \(SubscriptionDuration.editorSubscriptionPeriods.sorted().joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(c.secondaryLabel)
                    }
                    Divider()
                    Text("Localizations").font(.headline)
                    ForEach(Array((product.localizations ?? []).enumerated()), id: \.offset) { _, loc in
                        VStack(alignment: .leading) {
                            Text(loc.locale ?? "").font(.subheadline)
                            Text(loc.displayName ?? "").foregroundStyle(c.secondaryLabel)
                        }
                    }
                    HStack {
                        Button("Add en_US Localization") { model.addLocalization(locale: "en_US", to: loc) }
                        Button("Add Introductory Offer") { model.addOffer(to: loc, kind: .introductory) }
                        Button("Add Promotional Offer") { model.addOffer(to: loc, kind: .promotional) }
                        Button("Add Offer Code") { model.addOffer(to: loc, kind: .code) }
                    }
                    if let intro = product.introductoryOffer {
                        Text("Introductory: \(intro.paymentMode?.rawValue ?? "") ×\(intro.numberOfPeriods ?? 0) \(intro.subscriptionPeriod ?? "") — \(intro.displayPrice ?? "")")
                    }
                    ForEach(Array((product.adHocOffers ?? []).enumerated()), id: \.offset) { _, offer in
                        Text("Promo \(offer.offerID ?? ""): \(offer.paymentMode?.rawValue ?? "") ×\(offer.numberOfPeriods ?? 0) — \(offer.displayPrice ?? "")")
                    }
                    ForEach(Array((product.codeOffers ?? []).enumerated()), id: \.offset) { _, offer in
                        Text("Code \(offer.referenceName ?? ""): \(offer.eligibility?.joined(separator: ", ") ?? "")")
                    }
                } else {
                    Text("Select a product to inspect it.")
                        .foregroundStyle(c.secondaryLabel)
                        .padding()
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func groupList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Button("Add Subscription Group") { _ = model.addGroup() }
                ForEach(Array((model.configuration.subscriptionGroups ?? []).enumerated()), id: \.element.id) { index, group in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(group.name ?? group.id ?? "Group").font(.headline)
                            Spacer()
                            Button("Add Subscription") { _ = model.addSubscription(to: index) }
                            Button("Delete", role: .destructive) { model.removeGroup(at: index) }
                        }
                        ForEach(Array((group.subscriptions ?? []).enumerated()), id: \.offset) { _, sub in
                            HStack {
                                Text(sub.referenceName ?? sub.productID ?? "")
                                Spacer()
                                Text("Level \(sub.groupNumber ?? 0) · \(sub.recurringSubscriptionPeriod ?? "") · \(sub.displayPrice ?? "")")
                                    .foregroundStyle(c.secondaryLabel)
                            }
                        }
                    }
                    .padding(8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func offerList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.allProducts.filter { $0.product.type == .recurringSubscription }, id: \.location) { loc, product in
                    VStack(alignment: .leading) {
                        Text(product.referenceName ?? product.productID ?? "").font(.headline)
                        if let intro = product.introductoryOffer {
                            Text("Introductory: \(intro.paymentMode?.rawValue ?? "") ×\(intro.numberOfPeriods ?? 0) \(intro.subscriptionPeriod ?? "")")
                        }
                        ForEach(product.adHocOffers ?? [], id: \.offerID) { offer in
                            Text("Promo \(offer.offerID ?? ""): \(offer.displayPrice ?? "")")
                        }
                        ForEach(product.codeOffers ?? [], id: \.referenceName) { offer in
                            Text("Code \(offer.referenceName ?? "")")
                        }
                        HStack {
                            Button("Add Introductory") { model.addOffer(to: loc, kind: .introductory) }
                            Button("Add Promotional") { model.addOffer(to: loc, kind: .promotional) }
                            Button("Add Code") { model.addOffer(to: loc, kind: .code) }
                        }
                    }
                    .padding(8)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func localizationList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(model.localizationRows.enumerated()), id: \.offset) { _, row in
                    let (_, product, loc) = row
                    HStack {
                        Text(product.productID ?? "")
                        Spacer()
                        Text(loc.locale ?? "")
                        Text(loc.displayName ?? "")
                            .foregroundStyle(c.secondaryLabel)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func timelineList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.allProducts.filter { $0.product.type == .recurringSubscription }, id: \.location) { _, product in
                    HStack {
                        Text(product.referenceName ?? product.productID ?? "")
                        Spacer()
                        Text("\(product.recurringSubscriptionPeriod ?? "") → renews \(product.recurringSubscriptionPeriod ?? "")")
                            .foregroundStyle(c.secondaryLabel)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func settingsForm(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Test Settings").font(.headline)
                let settings = model.configuration.settings ?? Settings.defaults
                Picker("Storefront", selection: Binding(
                    get: { settings.storefront ?? "USA" },
                    set: { code in var s = settings; s.storefront = code; model.setSettings(s) }
                )) {
                    ForEach(StoreKitEditorModel.commonStorefronts, id: \.code) { sf in
                        Text("\(sf.code) — \(sf.name) (\(sf.currency))").tag(sf.code)
                    }
                }
                LabeledField(label: "Locale", text: settings.locale ?? "") { text in
                    var s = settings; s.locale = text; model.setSettings(s)
                }
                Stepper("Time Rate: \(settings.timeRate ?? 0)", value: Binding(
                    get: { settings.timeRate ?? 0 },
                    set: { rate in var s = settings; s.timeRate = rate; model.setSettings(s) }
                ), in: 0...1005)
                Text("Known time rates: \(validTimeRateValues.sorted().map(String.init).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(c.secondaryLabel)
                Toggle("Ask to Buy", isOn: Binding(
                    get: { settings.askToBuyEnabled ?? false },
                    set: { v in var s = settings; s.askToBuyEnabled = v; model.setSettings(s) }
                ))
                Toggle("Billing Issues", isOn: Binding(
                    get: { settings.billingIssuesEnabled ?? false },
                    set: { v in var s = settings; s.billingIssuesEnabled = v; model.setSettings(s) }
                ))
                Toggle("Renewal Billing Issues", isOn: Binding(
                    get: { settings.renewalBillingIssuesEnabled ?? false },
                    set: { v in var s = settings; s.renewalBillingIssuesEnabled = v; model.setSettings(s) }
                ))
                Toggle("Billing Grace Period", isOn: Binding(
                    get: { settings.billingGracePeriodEnabled ?? false },
                    set: { v in var s = settings; s.billingGracePeriodEnabled = v; model.setSettings(s) }
                ))
                Toggle("Disable Dialogs", isOn: Binding(
                    get: { settings.disableDialogs ?? false },
                    set: { v in var s = settings; s.disableDialogs = v; model.setSettings(s) }
                ))
                Toggle("Fail Transactions", isOn: Binding(
                    get: { settings.failTransactionsEnabled ?? false },
                    set: { v in var s = settings; s.failTransactionsEnabled = v; model.setSettings(s) }
                ))
                Divider()
                Text("App Policies").font(.headline)
                LabeledField(label: "EULA", text: model.configuration.appPolicies?.eula ?? "") { text in
                    model.mutate { $0.appPolicies = AppPolicies(eula: text, policies: $0.appPolicies?.policies) }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func validationList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Health \(model.healthScore) / 100").font(.title2)
                ForEach(model.validationIssues()) { issue in
                    HStack(alignment: .top) {
                        Image(systemName: issue.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(issue.severity == .error ? c.error : c.warning)
                        VStack(alignment: .leading) {
                            Text(issue.message)
                            Text("\(issue.category) · \(issue.path) · \(issue.rule)")
                                .font(.caption)
                                .foregroundStyle(c.secondaryLabel)
                        }
                        Spacer()
                        if let fix = issue.fix {
                            Button(fix.rawValue) { _ = model.applyFix(fix, at: issue.path) }
                        }
                    }
                    .padding(6)
                }
                if model.validationIssues().isEmpty {
                    Text("All diagnostics passed.").foregroundStyle(c.secondaryLabel)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func simulatorView(_ c: ShellColors) -> some View {
        @Bindable var simulation = model.simulation
        return ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Purchase Simulator").font(.headline)
                Text("In-memory only: no purchase leaves this editor.")
                    .foregroundStyle(c.secondaryLabel)
                Picker("Profile", selection: Binding(
                    get: { model.simulation.selectedProfileID },
                    set: { id in
                        if let p = model.simulation.availableProfiles.first(where: { $0.id == id }) {
                            model.simulation.applyProfile(p)
                        }
                    }
                )) {
                    Text("None").tag("")
                    ForEach(model.simulation.availableProfiles) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                Toggle("Offline", isOn: $simulation.isOfflineMode)
                Toggle("Ask to Buy", isOn: $simulation.isAskToBuyEnabled)
                Toggle("Simulate Network Failure", isOn: $simulation.shouldSimulateNetworkFailure)
                Toggle("Fail JWS Verification", isOn: $simulation.shouldFailVerification)
                Divider()
                ForEach(model.allProducts, id: \.location) { _, product in
                    HStack {
                        Text(product.referenceName ?? product.productID ?? "")
                        Spacer()
                        Text(product.displayPrice ?? "")
                        Button("Buy") { model.simulation.executePurchase(product: product) }
                    }
                }
                Divider()
                Text("Entitlements").font(.headline)
                ForEach(model.simulation.entitlements) { ent in
                    HStack {
                        Text(ent.productID)
                        Spacer()
                        Text(ent.isActive ? "Active" : "Inactive")
                            .foregroundStyle(ent.isActive ? c.success : c.secondaryLabel)
                    }
                }
                Button("Reset Simulator", role: .destructive) { model.simulation.resetSimulator() }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func transactionList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(model.simulation.transactions) { tx in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(tx.referenceName)
                            Text("\(tx.purchaseState) · \(tx.subscriptionCycleState)")
                                .font(.caption)
                                .foregroundStyle(c.secondaryLabel)
                        }
                        Spacer()
                        if tx.purchaseState == "pending" {
                            Button("Approve") { model.simulation.approvePendingTransaction(id: tx.id) }
                            Button("Decline") { model.simulation.declinePendingTransaction(id: tx.id) }
                        }
                        if tx.purchaseState == "purchased" {
                            Button("Refund") { model.simulation.triggerRefund(productID: tx.productID) }
                            Button("Revoke") { model.simulation.triggerRevocation(productID: tx.productID) }
                            Button("Expire") { model.simulation.simulateExpiration(productID: tx.productID) }
                            Button("Renew") { model.simulation.simulateRenewal(productID: tx.productID) }
                        }
                    }
                }
                if model.simulation.transactions.isEmpty {
                    Text("No simulated transactions yet. Buy a product in the Purchase Simulator.")
                        .foregroundStyle(c.secondaryLabel)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func templateList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(StoreKitEditorModel.templateNames, id: \.self) { name in
                    HStack {
                        Text(name).font(.headline)
                        Spacer()
                        Button("Apply") { model.applyTemplate(named: name) }
                    }
                    .padding(8)
                }
                Button("Load Default Workspace") { model.loadDefaultWorkspace() }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func historyList(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Button("Save Snapshot") { model.snapshot(reason: "Manual snapshot") }
                    Button("Undo") { model.undo() }.disabled(!model.canUndo)
                    Button("Redo") { model.redo() }.disabled(!model.canRedo)
                }
                ForEach(model.snapshots) { snap in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(snap.reason)
                            Text(snap.timestamp, style: .date)
                                .font(.caption)
                                .foregroundStyle(c.secondaryLabel)
                        }
                        Spacer()
                        Button("Restore") { model.restore(snap) }
                    }
                }
                if model.snapshots.isEmpty {
                    Text("No snapshots yet.").foregroundStyle(c.secondaryLabel)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compareView(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Compare with snapshot", selection: $compareSnapshot) {
                    Text("None").tag(nil as StoreKitSnapshot?)
                    ForEach(model.snapshots) { snap in
                        Text(snap.reason).tag(snap as StoreKitSnapshot?)
                    }
                }
                if let snap = compareSnapshot {
                    let diff = model.difference(from: snap.configuration)
                    if diff.isEmpty {
                        Text("No differences.").foregroundStyle(c.secondaryLabel)
                    } else {
                        ForEach(diff.addedProductIDs, id: \.self) { Text("Added: \($0)") }
                        ForEach(diff.removedProductIDs, id: \.self) { Text("Removed: \($0)") }
                        ForEach(diff.changedProductIDs, id: \.self) { Text("Changed: \($0)") }
                        ForEach(diff.priceChanges, id: \.0) { change in
                            Text("Price \(change.productID): \(change.old ?? "—") → \(change.new ?? "—")")
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func searchView(_ c: ShellColors) -> some View {
        VStack(spacing: 0) {
            TextField("Search products, groups, settings", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
                .padding(8)
            List(model.products(in: .products), id: \.location) { _, product in
                VStack(alignment: .leading) {
                    Text(product.referenceName ?? product.productID ?? "")
                    Text(product.productID ?? "")
                        .font(.caption)
                        .foregroundStyle(c.secondaryLabel)
                }
                .onTapGesture { model.selectedProductID = product.productID; model.selectedSection = .products }
            }
        }
    }

    private func commandPalette(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Type a command", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        switch command.lowercased() {
                        case "add product": model.addProduct()
                        case "add group": _ = model.addGroup()
                        case "validate": model.selectedSection = .validation
                        case "save": try? model.save()
                        case "undo": model.undo()
                        case "redo": model.redo()
                        default: break
                        }
                        command = ""
                    }
                Text("Commands: add product · add group · validate · save · undo · redo")
                    .foregroundStyle(c.secondaryLabel)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func logsView(_ c: ShellColors) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button("Clear Logs") { model.simulation.clearLogs() }
                    Button("Clear Activity") { model.simulation.clearActivityFeed() }
                }
                ForEach(model.simulation.activeLogs, id: \.self) { line in
                    Text(line).font(.system(.caption, design: .monospaced))
                }
                Divider()
                ForEach(model.simulation.activityEvents) { event in
                    Text("[\(event.category)] \(event.title): \(event.message)")
                        .font(.callout)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rawSourceView(_ c: ShellColors) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button("Reload from Model") { rawText = model.jsonText() }
                Button("Apply JSON") {
                    do { try model.setJSONText(rawText); model.clearProblem() } catch {
                        model.setProblem("\(error)")
                    }
                }
                Spacer()
                Text("Sorted pretty-printed JSON, as the file is written.")
                    .font(.caption)
                    .foregroundStyle(c.secondaryLabel)
            }
            .padding(.horizontal, 8)
            TextEditor(text: $rawText)
                .font(.system(.body, design: .monospaced))
                .padding(4)
        }
        .onAppear { rawText = model.jsonText() }
    }

    private func assetsNote(_ c: ShellColors) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assets are not part of the .storekit format.")
                .font(.headline)
            Text("Legacy's asset editor named local image files for products, but the format stores no images, so there is nothing to edit here. Product artwork lives in the app's asset catalog.")
                .foregroundStyle(c.secondaryLabel)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct LabeledField: View {
    let label: String
    let text: String
    let onChange: (String) -> Void

    var body: some View {
        HStack {
            Text(label).frame(width: 130, alignment: .trailing)
            TextField(label, text: Binding(get: { text }, set: onChange))
                .textFieldStyle(.roundedBorder)
        }
    }
}
