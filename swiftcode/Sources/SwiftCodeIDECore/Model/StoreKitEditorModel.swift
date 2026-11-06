import Foundation
import Observation
import StoreKitConfiguration

/// The `.storekit` editor's document model: a `StoreConfiguration`
/// (frameworks/storekit's `StoreKitConfiguration` — the `.storekit` file
/// model, which owns parsing and encoding; this file never parses JSON
/// itself), edited in place, with undo/redo, validation, fixes, snapshots,
/// templates, search and the simulation session.
///
/// Ported from Legacy's `Views/Utilities/StoreKit/` (13 files, 4,661
/// lines): the workspace session (`StoreKitWorkspaceManager.swift` — undo
/// stacks capped at 50, default workspace, 5 templates, recent files are
/// the workspace's job, not the document's), the validation service
/// (`StoreKitValidationService.swift` — health score, fix types), the
/// editors' product/group/offer/localization edits, and the sidebar's
/// sections. The AppKit window/split-view chrome (`StoreKitWindowController`,
/// `StoreKitWindowManager`, `StoreKitSplitViewController`) is not
/// reproduced: SwiftCode's workspace window hosts the editor. The asset editor
/// (`StoreKitAssetEditorView`, local image names) has no `.storekit`
/// equivalent — the format carries no images — so it is not reproduced.
/// Legacy's own `StoreKitConfig` schema is NOT the real `.storekit`
/// format (prices as numbers, unprefixed settings keys, `version: [Int]`,
/// type `"AutoRenewableSubscription"`, plural offer arrays); files Legacy
/// wrote in that schema are imported by `StoreKitLegacyImport`, never
/// treated as real `.storekit` files.
///
/// A file that carries App Store Connect synchronization keys
/// (`_applicationInternalID`, …) is read-only in the editor
/// (`StoreConfiguration.isSynchronized`); edits are refused with a
/// problem message instead of silently rewriting a synced file.

/// One sidebar section, mirroring Legacy's `StoreKitSidebarView` sections
/// and target sections.
public enum StoreKitEditorSection: String, CaseIterable, Identifiable, Sendable {
    case dashboard = "Dashboard"
    case explorer = "Explorer"
    case templates = "Templates"
    case history = "Version History"
    case compare = "Compare View"
    case products = "Products"
    case consumables = "Consumables"
    case nonConsumables = "Non Consumables"
    case autoRenewables = "Auto Renewables"
    case nonRenewables = "Non Renewables"
    case groups = "Subscription Groups"
    case timeline = "Subscription Timeline"
    case offers = "Offers"
    case storefronts = "Storefronts"
    case localization = "Localization"
    case assets = "Assets"
    case simulator = "Purchase Simulator"
    case transactions = "Transactions"
    case validation = "Validation"
    case search = "Search Center"
    case commandPalette = "Command Palette"
    case logs = "Logs"
    case rawSource = "Raw Source"
    case settings = "Settings"

    public var id: String { rawValue }

    public var group: String {
        switch self {
        case .dashboard, .explorer, .templates, .history, .compare: return "Workspace"
        case .products, .consumables, .nonConsumables, .autoRenewables, .nonRenewables: return "Products"
        case .groups, .timeline, .offers, .storefronts, .localization, .assets: return "Management"
        case .simulator, .transactions, .validation, .search, .commandPalette: return "Testing & Utilities"
        case .logs, .rawSource, .settings: return "Advanced"
        }
    }

    public var icon: String {
        switch self {
        case .dashboard: return "square.dashboard"
        case .explorer: return "folder"
        case .templates: return "square.grid.3x1.below.line.grid.1x2"
        case .history: return "clock.arrow.circlepath"
        case .compare: return "arrow.2.squarepath"
        case .products: return "cart"
        case .consumables: return "flame"
        case .nonConsumables: return "sparkles"
        case .autoRenewables: return "arrow.3.clockwise"
        case .nonRenewables: return "hourglass"
        case .groups: return "square.stack.3d.up"
        case .timeline: return "chart.bar.doc.horizontal"
        case .offers: return "tag"
        case .storefronts: return "globe"
        case .localization: return "character.bubble"
        case .assets: return "photo"
        case .simulator: return "play.circle"
        case .transactions: return "scroll"
        case .validation: return "exclamationmark.shield"
        case .search: return "magnifyingglass"
        case .commandPalette: return "terminal"
        case .logs: return "terminal.fill"
        case .rawSource: return "chevron.left.forwardslash.chevron.right"
        case .settings: return "gearshape"
        }
    }
}

/// Where a product lives in the file.
public enum StoreKitProductLocation: Equatable, Hashable, Sendable {
    case product(Int)
    case nonRenewing(Int)
    case subscription(group: Int, index: Int)
}

/// One validation finding, with the fix Legacy offered for it where the
/// framework's rule has one.
public struct StoreKitEditorIssue: Identifiable, Equatable, Sendable {
    public var id: String { rule + "|" + path }
    public enum Severity: String, Sendable { case error, warning, suggestion }
    public let severity: Severity
    public let category: String
    public let rule: String
    public let path: String
    public let message: String
    public let fix: StoreKitEditorFix?

    public init(severity: Severity, category: String, rule: String, path: String, message: String, fix: StoreKitEditorFix? = nil) {
        self.severity = severity
        self.category = category
        self.rule = rule
        self.path = path
        self.message = message
        self.fix = fix
    }
}

/// A one-click repair for a validation finding (Legacy's
/// `ValidationFixType`, adapted to the real format: prices are decimal
/// strings, identifiers are product IDs, group links are group IDs).
public enum StoreKitEditorFix: String, Sendable {
    case generateMissingLocalization = "Generate Missing English Localization"
    case fixPrice = "Set Price to Default ($0.99)"
    case fixEmptyIdentifier = "Generate Unique Product ID"
    case fixDuplicateIdentifier = "Rename Identifier to Unique"
    case fixMismatchGroup = "Re-align Group ID"
}

/// A saved revision of the configuration (Legacy's `SKVersionRevision`).
public struct StoreKitSnapshot: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var timestamp: Date
    public var reason: String
    public var configuration: StoreConfiguration

    public init(id: UUID = UUID(), timestamp: Date = Date(), reason: String, configuration: StoreConfiguration) {
        self.id = id
        self.timestamp = timestamp
        self.reason = reason
        self.configuration = configuration
    }
}

/// What changed between two configurations (Legacy's `StoreKitCompareView`).
public struct StoreKitConfigurationDifference: Sendable {
    public var addedProductIDs: [String]
    public var removedProductIDs: [String]
    public var changedProductIDs: [String]
    public var priceChanges: [(productID: String, old: String?, new: String?)]

    public init(addedProductIDs: [String] = [], removedProductIDs: [String] = [], changedProductIDs: [String] = [],
                priceChanges: [(productID: String, old: String?, new: String?)] = []) {
        self.addedProductIDs = addedProductIDs
        self.removedProductIDs = removedProductIDs
        self.changedProductIDs = changedProductIDs
        self.priceChanges = priceChanges
    }

    public var isEmpty: Bool { addedProductIDs.isEmpty && removedProductIDs.isEmpty && changedProductIDs.isEmpty }
}

/// A saved product filter (Legacy's `SKSmartFilter`).
public struct StoreKitSmartFilter: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var minPrice: Decimal?
    public var maxPrice: Decimal?
    public var productType: String?

    public init(id: UUID = UUID(), name: String, minPrice: Decimal? = nil, maxPrice: Decimal? = nil, productType: String? = nil) {
        self.id = id
        self.name = name
        self.minPrice = minPrice
        self.maxPrice = maxPrice
        self.productType = productType
    }

    /// Whether a product passes the filter. Prices are the file's decimal
    /// display-price strings; a product with no parseable price passes a
    /// price bound only when the bound is absent.
    public func matches(_ product: ConfiguredProduct) -> Bool {
        if let type = productType, product.type?.rawValue != type { return false }
        let price = product.displayPrice.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
        if let min = minPrice {
            guard let price, price >= min else { return false }
        }
        if let max = maxPrice {
            guard let price, price <= max else { return false }
        }
        return true
    }
}

@MainActor
@Observable
public final class StoreKitEditorModel {
    /// The file on disk, if the editor was opened on one.
    public let url: URL?
    /// The live configuration. All edits go through `mutate(_:)` so the
    /// undo stack and dirty flag stay correct.
    public private(set) var configuration: StoreConfiguration
    /// Whether the file ends with a newline (preserved on save, as
    /// `ConfigurationDocument` does).
    public private(set) var trailingNewline: Bool
    /// Whether the in-memory configuration differs from disk.
    public private(set) var isDirty = false
    /// Why the last edit, load or save was refused.
    public private(set) var problem: String?

    /// Sets the problem message (the Raw Source view reports a bad JSON
    /// paste this way).
    public func setProblem(_ message: String) { problem = message }

    /// Clears the problem banner.
    public func clearProblem() { problem = nil }
    /// The sidebar section showing.
    public var selectedSection: StoreKitEditorSection = .dashboard
    /// The selected product's ID, for the inspector.
    public var selectedProductID: String?
    /// The selected subscription group's ID.
    public var selectedGroupID: String?
    /// The search text filtering the product lists.
    public var searchText = ""
    /// The in-memory purchase simulator (Legacy's
    /// `StoreKitSimulationService`, ported to the real format).
    public let simulation: StoreKitSimulationSession
    /// Saved revisions, newest first.
    public private(set) var snapshots: [StoreKitSnapshot] = []
    /// Saved product filters.
    public var customFilters: [StoreKitSmartFilter] = [
        StoreKitSmartFilter(name: "Premium Offers Only", minPrice: Decimal(9.99), productType: "RecurringSubscription")
    ]
    private var undoStack: [StoreConfiguration] = []
    private var redoStack: [StoreConfiguration] = []

    /// Opens `url`.
    public init(url: URL, simulationCacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) throws {
        self.url = url
        let document = try ConfigurationDocument(contentsOf: url)
        configuration = document.configuration
        trailingNewline = document.trailingNewline
        simulation = StoreKitSimulationSession(cacheDirectory: simulationCacheDirectory)
    }

    /// A new empty configuration (the framework's template: default
    /// settings, no products, version 4.0, a fresh identifier).
    public init(simulationCacheDirectory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first) {
        self.url = nil
        configuration = StoreConfiguration.template()
        trailingNewline = false
        simulation = StoreKitSimulationSession(cacheDirectory: simulationCacheDirectory)
    }

    /// An in-memory document over an existing configuration (tests).
    /// The simulation session is in-memory only unless a cache
    /// directory is given.
    public init(configuration: StoreConfiguration, simulationCacheDirectory: URL? = nil) {
        self.url = nil
        self.configuration = configuration
        trailingNewline = false
        simulation = StoreKitSimulationSession(cacheDirectory: simulationCacheDirectory)
    }

    /// A synchronized file (App Store Connect keys present) is read-only
    /// in the editor.
    public var isReadOnly: Bool { configuration.isSynchronized }

    // MARK: - Persistence

    /// The file's bytes in canonical form.
    public func data() -> Data {
        ConfigurationDocument(configuration: configuration, trailingNewline: trailingNewline).data()
    }

    /// The file as sorted pretty-printed JSON text (the Raw Source view).
    public func jsonText() -> String { String(data: data(), encoding: .utf8) ?? "" }

    /// Replaces the configuration from JSON text; throws the framework's
    /// `ConfigurationReadError` when it is not a `.storekit` file.
    public func setJSONText(_ text: String) throws {
        let parsed = try StoreConfiguration(data: Data(text.utf8))
        mutate { $0 = parsed }
    }

    /// Writes the file atomically.
    public func save() throws {
        guard let url else { throw StoreKitEditorError.noFile }
        try data().write(to: url, options: .atomic)
        isDirty = false
    }

    /// Writes to a different file.
    public func save(to newURL: URL) throws {
        try data().write(to: newURL, options: .atomic)
        isDirty = false
    }

    // MARK: - Undo / redo (Legacy's `StoreKitWorkspaceSession`, cap 50)

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Records the current configuration, applies `edit`, marks dirty.
    /// Refused (with `problem` set) for synchronized files.
    public func mutate(_ edit: (inout StoreConfiguration) -> Void) {
        guard !isReadOnly else {
            problem = "This configuration was synchronized with App Store Connect and is read-only."
            return
        }
        pushUndo()
        edit(&configuration)
        isDirty = true
    }

    private func pushUndo() {
        undoStack.append(configuration)
        redoStack.removeAll()
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    public func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(configuration)
        configuration = prev
        isDirty = true
        simulation.log("Undid action.")
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(configuration)
        configuration = next
        isDirty = true
        simulation.log("Redid action.")
    }

    // MARK: - Products

    /// Every product with its location, in file order.
    public var allProducts: [(location: StoreKitProductLocation, product: ConfiguredProduct)] {
        var out: [(StoreKitProductLocation, ConfiguredProduct)] = []
        for (i, p) in (configuration.products ?? []).enumerated() { out.append((.product(i), p)) }
        for (i, p) in (configuration.nonRenewingSubscriptions ?? []).enumerated() { out.append((.nonRenewing(i), p)) }
        for (g, group) in (configuration.subscriptionGroups ?? []).enumerated() {
            for (i, p) in (group.subscriptions ?? []).enumerated() { out.append((.subscription(group: g, index: i), p)) }
        }
        return out
    }

    public func product(at location: StoreKitProductLocation) -> ConfiguredProduct? {
        switch location {
        case .product(let i): return configuration.products?[safe: i]
        case .nonRenewing(let i): return configuration.nonRenewingSubscriptions?[safe: i]
        case .subscription(let g, let i): return configuration.subscriptionGroups?[safe: g]?.subscriptions?[safe: i]
        }
    }

    public func setProduct(_ product: ConfiguredProduct, at location: StoreKitProductLocation) {
        mutate { c in
            switch location {
            case .product(let i):
                if var list = c.products, list.indices.contains(i) { list[i] = product; c.products = list }
            case .nonRenewing(let i):
                if var list = c.nonRenewingSubscriptions, list.indices.contains(i) { list[i] = product; c.nonRenewingSubscriptions = list }
            case .subscription(let g, let i):
                if var groups = c.subscriptionGroups, groups.indices.contains(g),
                   var list = groups[g].subscriptions, list.indices.contains(i) {
                    list[i] = product
                    groups[g].subscriptions = list
                    c.subscriptionGroups = groups
                }
            }
        }
    }

    /// The products of the section's list, filtered by the search text.
    public func products(in section: StoreKitEditorSection) -> [(location: StoreKitProductLocation, product: ConfiguredProduct)] {
        let base: [(StoreKitProductLocation, ConfiguredProduct)]
        switch section {
        case .consumables: base = allProducts.filter { $0.product.type == .consumable }
        case .nonConsumables: base = allProducts.filter { $0.product.type == .nonConsumable }
        case .autoRenewables: base = allProducts.filter { $0.product.type == .recurringSubscription }
        case .nonRenewables: base = allProducts.filter { $0.product.type == .nonRenewingSubscription }
        case .products, .explorer, .dashboard: base = allProducts
        default: base = allProducts
        }
        guard !searchText.isEmpty else { return base }
        let q = searchText.lowercased()
        return base.filter { (_, p) in
            (p.productID ?? "").lowercased().contains(q)
                || (p.referenceName ?? "").lowercased().contains(q)
                || (p.localizations ?? []).contains { ($0.displayName ?? "").lowercased().contains(q) }
        }
    }

    /// The next free numeric internal identifier (one past the largest
    /// internal ID used by any product or offer).
    public func nextInternalID() -> String {
        let used = allProducts.flatMap { (_, p) in
            [p.internalID] + (p.introductoryOffer.map { [$0.internalID] } ?? [])
                + (p.adHocOffers ?? []).map(\.internalID) + (p.codeOffers ?? []).map(\.internalID)
        }.compactMap { $0 }.compactMap(Int.init)
        return String((used.max() ?? 0) + 1)
    }

    /// The next free numeric subscription-group identifier.
    public func nextGroupID() -> String {
        let used = (configuration.subscriptionGroups ?? []).compactMap(\.id).compactMap(Int.init)
        return String((used.max() ?? 0) + 1)
    }

    private func uniqueProductID(base: String) -> String {
        let used = Set(allProducts.compactMap { $0.product.productID })
        if !used.contains(base) { return base }
        var n = 2
        while used.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// A new product of the given kind, appended in the right list.
    @discardableResult
    public func addProduct(kind: ProductKind = .nonConsumable) -> StoreKitProductLocation {
        let id = uniqueProductID(base: "com.example.newproduct")
        let product = ConfiguredProduct(
            type: kind, productID: id, referenceName: "New Product", internalID: nextInternalID(),
            displayPrice: "0.99", familyShareable: false,
            localizations: [Localization(locale: "en_US", displayName: "New Product", description: "")])
        var location: StoreKitProductLocation = .product(0)
        mutate { c in
            switch kind {
            case .consumable, .nonConsumable:
                c.products = (c.products ?? []) + [product]
                location = .product((c.products ?? []).count - 1)
            case .nonRenewingSubscription:
                c.nonRenewingSubscriptions = (c.nonRenewingSubscriptions ?? []) + [product]
                location = .nonRenewing((c.nonRenewingSubscriptions ?? []).count - 1)
            default:
                // A subscription needs a group; without one it lands in
                // `products` and validation flags the misplaced type.
                c.products = (c.products ?? []) + [product]
                location = .product((c.products ?? []).count - 1)
            }
        }
        selectedProductID = id
        return location
    }

    /// Removes the product at a location (no-op for an out-of-range index).
    public func removeProduct(at location: StoreKitProductLocation) {
        mutate { c in
            switch location {
            case .product(let i):
                if var list = c.products, list.indices.contains(i) { list.remove(at: i); c.products = list }
            case .nonRenewing(let i):
                if var list = c.nonRenewingSubscriptions, list.indices.contains(i) { list.remove(at: i); c.nonRenewingSubscriptions = list }
            case .subscription(let g, let i):
                if var groups = c.subscriptionGroups, groups.indices.contains(g),
                   var list = groups[g].subscriptions, list.indices.contains(i) {
                    list.remove(at: i)
                    groups[g].subscriptions = list
                    c.subscriptionGroups = groups
                }
            }
        }
    }

    /// Duplicates a product with a fresh product ID and internal ID.
    @discardableResult
    public func duplicateProduct(at location: StoreKitProductLocation) -> StoreKitProductLocation? {
        guard var copy = product(at: location) else { return nil }
        copy.productID = uniqueProductID(base: (copy.productID ?? "com.example.product") + "-copy")
        copy.internalID = nextInternalID()
        copy.referenceName = (copy.referenceName ?? "") + " Copy"
        var newLocation: StoreKitProductLocation?
        mutate { c in
            switch location {
            case .product(let i):
                if var list = c.products, list.indices.contains(i) {
                    list.insert(copy, at: i + 1)
                    c.products = list
                    newLocation = .product(i + 1)
                }
            case .nonRenewing(let i):
                if var list = c.nonRenewingSubscriptions, list.indices.contains(i) {
                    list.insert(copy, at: i + 1)
                    c.nonRenewingSubscriptions = list
                    newLocation = .nonRenewing(i + 1)
                }
            case .subscription(let g, let i):
                if var groups = c.subscriptionGroups, groups.indices.contains(g),
                   var list = groups[g].subscriptions, list.indices.contains(i) {
                    list.insert(copy, at: i + 1)
                    groups[g].subscriptions = list
                    c.subscriptionGroups = groups
                    newLocation = .subscription(group: g, index: i + 1)
                }
            }
        }
        return newLocation
    }

    // MARK: - Subscription groups

    @discardableResult
    public func addGroup(name: String = "New Group") -> Int {
        let group = SubscriptionGroup(id: nextGroupID(), name: name, localizations: [], subscriptions: [])
        var index = 0
        mutate { c in
            c.subscriptionGroups = (c.subscriptionGroups ?? []) + [group]
            index = (c.subscriptionGroups ?? []).count - 1
        }
        selectedGroupID = group.id
        return index
    }

    public func removeGroup(at index: Int) {
        mutate { c in
            if var groups = c.subscriptionGroups, groups.indices.contains(index) {
                groups.remove(at: index)
                c.subscriptionGroups = groups
            }
        }
    }

    /// A new auto-renewable subscription in a group, at the next level.
    @discardableResult
    public func addSubscription(to groupIndex: Int, period: String = "P1M") -> StoreKitProductLocation? {
        guard let group = configuration.subscriptionGroups?[safe: groupIndex], let groupID = group.id else { return nil }
        let id = uniqueProductID(base: "com.example.newsubscription")
        let level = ((group.subscriptions ?? []).compactMap(\.groupNumber).max() ?? 0) + 1
        let product = ConfiguredProduct(
            type: .recurringSubscription, productID: id, referenceName: "New Subscription",
            internalID: nextInternalID(), displayPrice: "9.99", familyShareable: false,
            localizations: [Localization(locale: "en_US", displayName: "New Subscription", description: "")],
            subscriptionGroupID: groupID, groupNumber: level, recurringSubscriptionPeriod: period)
        var location: StoreKitProductLocation?
        mutate { c in
            if var groups = c.subscriptionGroups, groups.indices.contains(groupIndex) {
                var list = groups[groupIndex].subscriptions ?? []
                list.append(product)
                groups[groupIndex].subscriptions = list
                c.subscriptionGroups = groups
                location = .subscription(group: groupIndex, index: list.count - 1)
            }
        }
        selectedProductID = id
        return location
    }

    // MARK: - Offers & localizations

    /// A new offer on a subscription: introductory (one only), promotional
    /// or code.
    public func addOffer(to location: StoreKitProductLocation, kind: StoreKitOfferKind) {
        guard var product = product(at: location) else { return }
        let offer = Offer(internalID: nextInternalID(), paymentMode: .free, subscriptionPeriod: "P1W",
                          numberOfPeriods: 1, displayPrice: product.displayPrice)
        switch kind {
        case .introductory: product.introductoryOffer = offer
        case .promotional:
            var list = product.adHocOffers ?? []
            var o = offer
            o.offerID = "offer-\(list.count + 1)"
            list.append(o)
            product.adHocOffers = list
        case .code:
            var list = product.codeOffers ?? []
            var o = offer
            o.referenceName = "CODE\(list.count + 1)"
            o.eligibility = ["new"]
            list.append(o)
            product.codeOffers = list
        }
        setProduct(product, at: location)
    }

    public func removeOffer(at offerIndex: Int, kind: StoreKitOfferKind, from location: StoreKitProductLocation) {
        guard var product = product(at: location) else { return }
        switch kind {
        case .introductory: product.introductoryOffer = nil
        case .promotional:
            if var list = product.adHocOffers, list.indices.contains(offerIndex) {
                list.remove(at: offerIndex)
                product.adHocOffers = list
            }
        case .code:
            if var list = product.codeOffers, list.indices.contains(offerIndex) {
                list.remove(at: offerIndex)
                product.codeOffers = list
            }
        }
        setProduct(product, at: location)
    }

    /// Adds an empty localization for a locale to a product.
    public func addLocalization(locale: String, to location: StoreKitProductLocation) {
        guard var product = product(at: location) else { return }
        guard !(product.localizations ?? []).contains(where: { $0.locale == locale }) else { return }
        var list = product.localizations ?? []
        list.append(Localization(locale: locale, displayName: product.referenceName ?? "", description: ""))
        product.localizations = list
        setProduct(product, at: location)
    }

    /// The localization matrix: every (product, localization) pair, for
    /// the Localization section (Legacy's `Localization Matrix`).
    public var localizationRows: [(location: StoreKitProductLocation, product: ConfiguredProduct, localization: Localization)] {
        allProducts.flatMap { (loc, p) in
            (p.localizations ?? []).map { (loc, p, $0) }
        }
    }

    // MARK: - Settings & storefronts

    public func setSettings(_ settings: Settings) {
        mutate { $0.settings = settings }
    }

    /// Common storefronts for the storefront picker (ISO 3166-1 alpha-3
    /// code + currency); the field itself takes any three-letter code.
    public static let commonStorefronts: [(code: String, name: String, currency: String)] = [
        ("USA", "United States", "USD"), ("CAN", "Canada", "CAD"), ("MEX", "Mexico", "MXN"),
        ("GBR", "United Kingdom", "GBP"), ("FRA", "France", "EUR"), ("DEU", "Germany", "EUR"),
        ("ITA", "Italy", "EUR"), ("ESP", "Spain", "EUR"), ("NLD", "Netherlands", "EUR"),
        ("AUS", "Australia", "AUD"), ("NZL", "New Zealand", "NZD"), ("JPN", "Japan", "JPY"),
        ("KOR", "South Korea", "KRW"), ("CHN", "China", "CNY"), ("IND", "India", "INR"),
        ("BRA", "Brazil", "BRL"), ("CHE", "Switzerland", "CHF"), ("SWE", "Sweden", "SEK"),
    ]

    // MARK: - Validation

    /// The framework's findings, mapped to editor issues with Legacy's
    /// categories and fixes, plus Legacy's empty-group suggestion.
    public func validationIssues() -> [StoreKitEditorIssue] {
        var issues = configuration.validate().map { issue in
            StoreKitEditorIssue(severity: issue.severity == .error ? .error : .warning,
                                category: Self.category(for: issue.rule), rule: issue.rule,
                                path: issue.path, message: issue.message, fix: Self.fix(for: issue.rule))
        }
        for (g, group) in (configuration.subscriptionGroups ?? []).enumerated()
            where (group.subscriptions ?? []).isEmpty {
            issues.append(StoreKitEditorIssue(
                severity: .suggestion, category: "Configuration", rule: "group.empty",
                path: "subscriptionGroups[\(g)]",
                message: "Subscription group '\(group.name ?? group.id ?? "")' contains no auto-renewable subscriptions."))
        }
        return issues
    }

    public var errors: [StoreKitEditorIssue] { validationIssues().filter { $0.severity == .error } }
    public var warnings: [StoreKitEditorIssue] { validationIssues().filter { $0.severity == .warning } }
    public var isValid: Bool { errors.isEmpty }

    /// Legacy's health score: 100, minus 15 per error, 8 per warning,
    /// 3 per suggestion, clamped to 0…100.
    public var healthScore: Int {
        let issues = validationIssues()
        var score = 100
        for issue in issues {
            switch issue.severity {
            case .error: score -= 15
            case .warning: score -= 8
            case .suggestion: score -= 3
            }
        }
        return max(0, min(100, score))
    }

    private static func category(for rule: String) -> String {
        if rule.hasPrefix("product.") || rule.hasPrefix("subscription.") || rule.hasPrefix("offer.")
            || rule.hasPrefix("internalID.") || rule.hasPrefix("price.") { return "Identifier" }
        if rule.hasPrefix("localization.") || rule.hasPrefix("policy.") { return "Localization" }
        if rule.hasPrefix("group.") { return "Relationship" }
        if rule.hasPrefix("settings.") { return "Configuration" }
        if rule.hasPrefix("identifier.") || rule.hasPrefix("version.") { return "Schema" }
        return "Configuration"
    }

    private static func fix(for rule: String) -> StoreKitEditorFix? {
        switch rule {
        case "localization.locale.missing", "localization.displayName.missing", "product.referenceName.missing":
            return .generateMissingLocalization
        case "price.format", "price.missing": return .fixPrice
        case "product.id.missing", "internalID.missing": return .fixEmptyIdentifier
        case "product.id.duplicate", "internalID.duplicate": return .fixDuplicateIdentifier
        case "subscription.groupID.mismatch": return .fixMismatchGroup
        default: return nil
        }
    }

    /// Applies a one-click fix at a finding's path. Returns false when
    /// the path no longer resolves.
    @discardableResult
    public func applyFix(_ fix: StoreKitEditorFix, at path: String) -> Bool {
        guard let location = Self.location(for: path) else { return false }
        guard var product = product(at: location) else { return false }
        switch fix {
        case .generateMissingLocalization:
            if (product.localizations ?? []).isEmpty {
                product.localizations = [Localization(locale: "en_US", displayName: product.referenceName ?? product.productID ?? "Product", description: "")]
            } else if let i = product.localizations?.firstIndex(where: { ($0.displayName ?? "").isEmpty }) {
                product.localizations?[i].displayName = product.referenceName ?? product.productID ?? "Product"
            } else { return false }
        case .fixPrice:
            product.displayPrice = "0.99"
        case .fixEmptyIdentifier:
            if (product.productID ?? "").isEmpty {
                product.productID = uniqueProductID(base: "com.example.\((product.referenceName ?? "product").lowercased().filter { $0.isLetter || $0.isNumber })")
            }
            if (product.internalID ?? "").isEmpty { product.internalID = nextInternalID() }
        case .fixDuplicateIdentifier:
            if let existing = product.productID { product.productID = uniqueProductID(base: existing + "-2") }
            if let existing = product.internalID, allProducts.contains(where: { $0.product.internalID == existing && $0.product.productID != product.productID }) {
                product.internalID = nextInternalID()
            }
        case .fixMismatchGroup:
            if case .subscription(let g, _) = location {
                product.subscriptionGroupID = configuration.subscriptionGroups?[safe: g]?.id
            } else { return false }
        }
        setProduct(product, at: location)
        return true
    }

    /// Resolves a validation path (`products[0]`,
    /// `subscriptionGroups[1].subscriptions[0]`,
    /// `nonRenewingSubscriptions[0]`, or a path with a trailing key)
    /// to a product location.
    static func location(for path: String) -> StoreKitProductLocation? {
        let parts = path.split(separator: ".").map(String.init)
        guard let first = parts.first else { return nil }
        func index(of token: String) -> Int? {
            guard let open = token.firstIndex(of: "["), let close = token.firstIndex(of: "]") else { return nil }
            return Int(token[token.index(after: open)..<close])
        }
        if first.hasPrefix("products["), let i = index(of: first) { return .product(i) }
        if first.hasPrefix("nonRenewingSubscriptions["), let i = index(of: first) { return .nonRenewing(i) }
        if first.hasPrefix("subscriptionGroups["), let g = index(of: first), parts.count > 1,
           parts[1].hasPrefix("subscriptions["), let i = index(of: parts[1]) {
            return .subscription(group: g, index: i)
        }
        return nil
    }

    // MARK: - Snapshots & compare

    /// Saves the current configuration as a named revision.
    public func snapshot(reason: String) {
        snapshots.insert(StoreKitSnapshot(reason: reason, configuration: configuration), at: 0)
        simulation.log("Saved version snapshot: \(reason).")
    }

    /// Restores a snapshot (undoable).
    public func restore(_ snapshot: StoreKitSnapshot) {
        mutate { $0 = snapshot.configuration }
        simulation.log("Restored version snapshot: \(snapshot.reason).")
    }

    /// The difference between the current configuration and another
    /// (Legacy's `StoreKitCompareView`). Duplicate product IDs keep the
    /// first occurrence on each side, so an invalid file cannot crash
    /// the comparison.
    public func difference(from other: StoreConfiguration) -> StoreKitConfigurationDifference {
        func byID(_ products: [ConfiguredProduct]) -> [String: ConfiguredProduct] {
            var out: [String: ConfiguredProduct] = [:]
            for p in products { if let id = p.productID, out[id] == nil { out[id] = p } }
            return out
        }
        let mine = byID(allProducts.map(\.product))
        let theirs = byID(other.allProducts)
        let added = mine.keys.filter { theirs[$0] == nil }.sorted()
        let removed = theirs.keys.filter { mine[$0] == nil }.sorted()
        var changed: [String] = []
        var prices: [(String, String?, String?)] = []
        for id in mine.keys.sorted() where theirs[id] != nil {
            if mine[id] != theirs[id] {
                changed.append(id)
                if mine[id]?.displayPrice != theirs[id]?.displayPrice {
                    prices.append((id, theirs[id]?.displayPrice, mine[id]?.displayPrice))
                }
            }
        }
        return StoreKitConfigurationDifference(addedProductIDs: added, removedProductIDs: removed,
                                               changedProductIDs: changed, priceChanges: prices)
    }

    // MARK: - Templates & default workspace

    /// Legacy's five starter templates, rewritten in the real `.storekit`
    /// format (Legacy's template products carried no internal IDs and its
    /// subscription type string was wrong; these carry both correctly).
    public static let templateNames = ["Premium Unlock", "Pro Version", "Consumables / Tips", "Streaming Service", "Mixed Catalog"]

    /// Replaces the configuration with a template (undoable).
    public func applyTemplate(named name: String) {
        let config: StoreConfiguration
        switch name {
        case "Premium Unlock":
            config = StoreConfiguration.template().with(
                products: [ConfiguredProduct(type: .nonConsumable, productID: "com.app.premium_lifetime",
                                              referenceName: "Premium Lifetime Unlock", internalID: "1",
                                              displayPrice: "29.99", familyShareable: false,
                                              localizations: [Localization(locale: "en_US", displayName: "Premium Lifetime Unlock", description: "Unlock all features forever.")])])
        case "Pro Version":
            config = StoreConfiguration.template().with(subscriptionGroups: [
                SubscriptionGroup(id: "1", name: "Pro Group", localizations: [], subscriptions: [
                    ConfiguredProduct(type: .recurringSubscription, productID: "com.app.pro_monthly", referenceName: "Pro Monthly Plan",
                                      internalID: "1", displayPrice: "9.99", familyShareable: false,
                                      localizations: [Localization(locale: "en_US", displayName: "Pro Monthly Plan", description: "Get unlimited workspace access.")],
                                      subscriptionGroupID: "1", groupNumber: 1, recurringSubscriptionPeriod: "P1M",
                                      introductoryOffer: Offer(internalID: "2", paymentMode: .free, subscriptionPeriod: "P1W", numberOfPeriods: 1, displayPrice: "0.00")),
                    ConfiguredProduct(type: .recurringSubscription, productID: "com.app.pro_yearly", referenceName: "Pro Yearly Plan",
                                      internalID: "3", displayPrice: "79.99", familyShareable: false,
                                      localizations: [Localization(locale: "en_US", displayName: "Pro Yearly Plan", description: "Annual discount plan.")],
                                      subscriptionGroupID: "1", groupNumber: 2, recurringSubscriptionPeriod: "P1Y",
                                      introductoryOffer: Offer(internalID: "4", paymentMode: .free, subscriptionPeriod: "P2W", numberOfPeriods: 1, displayPrice: "0.00")),
                ])
            ])
        case "Consumables / Tips":
            config = StoreConfiguration.template().with(products: [
                ConfiguredProduct(type: .consumable, productID: "com.app.tip_small", referenceName: "Small Tip Don",
                                  internalID: "1", displayPrice: "0.99", familyShareable: false,
                                  localizations: [Localization(locale: "en_US", displayName: "Small Tip", description: "Support the developer with a small tip!")]),
                ConfiguredProduct(type: .consumable, productID: "com.app.tip_large", referenceName: "Large Tip Don",
                                  internalID: "2", displayPrice: "4.99", familyShareable: false,
                                  localizations: [Localization(locale: "en_US", displayName: "Large Tip", description: "Show major support with a generous tip!")]),
            ])
        case "Streaming Service":
            config = StoreConfiguration.template().with(subscriptionGroups: [
                SubscriptionGroup(id: "1", name: "Streaming Group", localizations: [], subscriptions: [
                    ConfiguredProduct(type: .recurringSubscription, productID: "com.app.stream_basic", referenceName: "Basic Tier",
                                      internalID: "1", displayPrice: "5.99", familyShareable: false,
                                      localizations: [Localization(locale: "en_US", displayName: "Basic Stream", description: "HD stream with ads.")],
                                      subscriptionGroupID: "1", groupNumber: 1, recurringSubscriptionPeriod: "P1M"),
                    ConfiguredProduct(type: .recurringSubscription, productID: "com.app.stream_ultra", referenceName: "Ultra 4K Tier",
                                      internalID: "2", displayPrice: "14.99", familyShareable: false,
                                      localizations: [Localization(locale: "en_US", displayName: "Ultra 4K Stream", description: "4K stream on 4 devices simultaneously.")],
                                      subscriptionGroupID: "1", groupNumber: 2, recurringSubscriptionPeriod: "P1M"),
                ])
            ])
        case "Mixed Catalog":
            config = StoreConfiguration.template().with(
                products: [
                    ConfiguredProduct(type: .nonConsumable, productID: "com.app.ad_free_lifetime", referenceName: "Ad Free Lifetime",
                                      internalID: "1", displayPrice: "4.99", familyShareable: false,
                                      localizations: [Localization(locale: "en_US", displayName: "Ad Free Lifetime", description: "Remove all advertisements forever.")]),
                    ConfiguredProduct(type: .consumable, productID: "com.app.coins_pack", referenceName: "1000 Coins Pack",
                                      internalID: "2", displayPrice: "2.99", familyShareable: false,
                                      localizations: [Localization(locale: "en_US", displayName: "1000 Coins Pack", description: "Buy 1000 gold coins for in-game purchases.")]),
                ],
                nonRenewingSubscriptions: [
                    ConfiguredProduct(type: .nonRenewingSubscription, productID: "com.app.pass_3months", referenceName: "3 Month Seasonal Pass",
                                      internalID: "3", displayPrice: "9.99", familyShareable: false,
                                      localizations: [Localization(locale: "en_US", displayName: "Seasonal 3 Month Pass", description: "Get seasonal benefits for 3 months.")]),
                ],
                subscriptionGroups: [
                    SubscriptionGroup(id: "1", name: "VIP Club", localizations: [], subscriptions: [
                        ConfiguredProduct(type: .recurringSubscription, productID: "com.app.vip_monthly", referenceName: "Monthly VIP Pass",
                                          internalID: "4", displayPrice: "12.99", familyShareable: false,
                                          localizations: [Localization(locale: "en_US", displayName: "VIP Monthly Club", description: "Unlock exclusive features and daily rewards.")],
                                          subscriptionGroupID: "1", groupNumber: 1, recurringSubscriptionPeriod: "P1M",
                                          introductoryOffer: Offer(internalID: "5", paymentMode: .free, subscriptionPeriod: "P1W", numberOfPeriods: 1, displayPrice: "0.00")),
                    ])
                ])
        default:
            return
        }
        mutate { $0 = config }
        simulation.log("Applied template: '\(name)'.")
    }

    /// Legacy's default workspace: a lifetime unlock, an AI-credits
    /// consumable, and a Pro group with a monthly subscription — in the
    /// real format (Legacy's default identifier,
    /// `"default_storekit_config"`, is not a valid 8-hex identifier, so
    /// the template's fresh identifier is used instead).
    public func loadDefaultWorkspace() {
        var config = StoreConfiguration.template()
        config.products = [
            ConfiguredProduct(type: .nonConsumable, productID: "com.swiftcode.premium_unlock", referenceName: "Premium Lifetime Unlock",
                              internalID: "1", displayPrice: "19.99", familyShareable: false,
                              localizations: [Localization(locale: "en_US", displayName: "Premium Lifetime Unlock", description: "Unlock all advanced features permanently.")]),
            ConfiguredProduct(type: .consumable, productID: "com.swiftcode.credits_pack", referenceName: "100 AI Credits Consumable",
                              internalID: "2", displayPrice: "1.99", familyShareable: false,
                              localizations: [Localization(locale: "en_US", displayName: "100 AI Credits", description: "Consumable pack of 100 AI assist credits.")]),
        ]
        var settings = Settings.defaults
        settings.billingGracePeriodEnabled = true
        settings.renewalBillingIssuesEnabled = true
        config.settings = settings
        config.subscriptionGroups = [
            SubscriptionGroup(id: "1", name: "Pro Membership Group", localizations: [], subscriptions: [
                ConfiguredProduct(type: .recurringSubscription, productID: "com.swiftcode.pro_monthly", referenceName: "Pro Monthly Subscription",
                                  internalID: "3", displayPrice: "9.99", familyShareable: false,
                                  localizations: [Localization(locale: "en_US", displayName: "Pro Monthly", description: "Get unlimited cloud workspaces & AI assistance monthly.")],
                                  subscriptionGroupID: "1", groupNumber: 1, recurringSubscriptionPeriod: "P1M",
                                  introductoryOffer: Offer(internalID: "4", paymentMode: .free, subscriptionPeriod: "P1W", numberOfPeriods: 1, displayPrice: "0.00"),
                                  adHocOffers: [Offer(internalID: "5", offerID: "promo_half_off", referenceName: "Half Off Summer Promo",
                                                      paymentMode: .payAsYouGo, subscriptionPeriod: "P1M", numberOfPeriods: 3, displayPrice: "4.99")]),
            ])
        ]
        mutate { $0 = config }
    }
}

/// Which offer list a new offer joins.
public enum StoreKitOfferKind: Sendable {
    case introductory
    case promotional
    case code
}

public enum StoreKitEditorError: Error, CustomStringConvertible {
    case noFile

    public var description: String {
        switch self {
        case .noFile: return "The StoreKit editor has no file to save to."
        }
    }
}

private extension StoreConfiguration {
    /// A copy with the given product lists (templates build on
    /// `StoreConfiguration.template()`).
    func with(products: [ConfiguredProduct]? = nil, nonRenewingSubscriptions: [ConfiguredProduct]? = nil,
              subscriptionGroups: [SubscriptionGroup]? = nil) -> StoreConfiguration {
        var copy = self
        if let products { copy.products = products }
        if let nonRenewingSubscriptions { copy.nonRenewingSubscriptions = nonRenewingSubscriptions }
        if let subscriptionGroups { copy.subscriptionGroups = subscriptionGroups }
        return copy
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        get { indices.contains(index) ? self[index] : nil }
        set {
            guard indices.contains(index), let newValue else { return }
            self[index] = newValue
        }
    }
}
