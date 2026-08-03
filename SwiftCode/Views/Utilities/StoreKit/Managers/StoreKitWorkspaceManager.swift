import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers

@Observable
@MainActor
public final class StoreKitWorkspaceSession: Identifiable {
    public nonisolated let id = UUID()
    public var activeConfig: StoreKitConfig = StoreKitConfig() {
        didSet {
            StoreKitWorkspaceManager.shared.activeConfig = activeConfig
        }
    }
    public var activeURL: URL? = nil
    public var selectedSection: String = "Dashboard"

    // Undo/Redo Stacks
    public var undoStack: [StoreKitConfig] = []
    public var redoStack: [StoreKitConfig] = []

    public init(fileURL: URL? = nil) {
        if let fileURL = fileURL {
            loadDocument(from: fileURL)
        } else {
            loadDefaultWorkspace()
        }
    }

    public func pushToUndoStack() {
        undoStack.append(activeConfig)
        redoStack.removeAll()
        if undoStack.count > 50 {
            undoStack.removeFirst()
        }
    }

    public func undo() {
        guard !undoStack.isEmpty else { return }
        let prev = undoStack.removeLast()
        redoStack.append(activeConfig)
        activeConfig = prev
        StoreKitSimulationService.shared.log("Undid action.")
    }

    public func redo() {
        guard !redoStack.isEmpty else { return }
        let next = redoStack.removeLast()
        undoStack.append(activeConfig)
        activeConfig = next
        StoreKitSimulationService.shared.log("Redid action.")
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public func loadDefaultWorkspace() {
        let defaultProducts: [SKProduct] = [
            SKProduct(productID: "com.swiftcode.premium_unlock", referenceName: "Premium Lifetime Unlock", type: "NonConsumable", localizations: [
                SKLocalization(locale: "en_US", displayName: "Premium Lifetime Unlock", description: "Unlock all advanced features permanently.")
            ], price: 19.99),
            SKProduct(productID: "com.swiftcode.credits_pack", referenceName: "100 AI Credits Consumable", type: "Consumable", localizations: [
                SKLocalization(locale: "en_US", displayName: "100 AI Credits", description: "Consumable pack of 100 AI assist credits.")
            ], price: 1.99)
        ]

        let defaultGroup = SKSubscriptionGroup(groupName: "Pro Membership Group", subscriptions: [
            SKSubscription(productID: "com.swiftcode.pro_monthly", referenceName: "Pro Monthly Subscription", localizations: [
                SKLocalization(locale: "en_US", displayName: "Pro Monthly", description: "Get unlimited cloud workspaces & AI assistance monthly.")
            ], price: 9.99, subscriptionGroupID: "Pro Membership Group", subscriptionPeriod: "P1M", introductoryOffers: [
                SKIntroductoryOffer(numberOfPeriods: 1, paymentMode: "freeTrial", price: 0.0, subscriptionPeriod: "P1W")
            ], promotionalOffers: [
                SKPromotionalOffer(offerID: "promo_half_off", referenceName: "Half Off Summer Promo", paymentMode: "payAsYouGo", price: 4.99, numberOfPeriods: 3, subscriptionPeriod: "P1M")
            ])
        ])

        activeConfig = StoreKitConfig(
            identifier: "default_storekit_config",
            settings: SKSettings(billingGracePeriodEnabled: true, billingRetryEnabled: true),
            products: defaultProducts,
            subscriptionGroups: [defaultGroup],
            nonRenewingSubscriptions: [],
            version: [4, 0]
        )
        activeURL = nil
    }

    public func loadDocument(from url: URL) {
        do {
            let config = try StoreKitParser.shared.parse(url: url)
            activeConfig = config
            activeURL = url
            undoStack.removeAll()
            redoStack.removeAll()
            StoreKitSimulationService.shared.log("Successfully loaded StoreKit file: \(url.lastPathComponent)")
        } catch {
            StoreKitSimulationService.shared.log("Error loading StoreKit file: \(error.localizedDescription)")
        }
    }

    public func saveDocument() {
        guard let url = activeURL else {
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.json, UTType(filenameExtension: "storekit")!]
            savePanel.nameFieldStringValue = "Configuration.storekit"
            savePanel.title = "Save StoreKit Configuration"
            if savePanel.runModal() == .OK, let selectedURL = savePanel.url {
                saveDocument(to: selectedURL)
            }
            return
        }
        saveDocument(to: url)
    }

    public func saveDocument(to url: URL) {
        do {
            try StoreKitEncoder.shared.encode(to: url, config: activeConfig)
            activeURL = url
            StoreKitWorkspaceManager.shared.addRecent(url: url)
            StoreKitSimulationService.shared.log("Successfully saved StoreKit configuration to disk.")
        } catch {
            StoreKitSimulationService.shared.log("Error saving StoreKit file: \(error.localizedDescription)")
        }
    }

    public func loadTemplate(name: String) {
        pushToUndoStack()
        switch name {
        case "Premium Unlock":
            activeConfig.products = [
                SKProduct(productID: "com.app.premium_lifetime", referenceName: "Premium Lifetime Unlock", type: "NonConsumable", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Premium Lifetime Unlock", description: "Unlock all features forever.")
                ], price: 29.99)
            ]
            activeConfig.subscriptionGroups = []
            activeConfig.nonRenewingSubscriptions = []

        case "Pro Version":
            activeConfig.products = []
            let proGroup = SKSubscriptionGroup(groupName: "Pro Group", subscriptions: [
                SKSubscription(productID: "com.app.pro_monthly", referenceName: "Pro Monthly Plan", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Pro Monthly Plan", description: "Get unlimited workspace access.")
                ], price: 9.99, subscriptionGroupID: "Pro Group", subscriptionPeriod: "P1M", introductoryOffers: [
                    SKIntroductoryOffer(numberOfPeriods: 1, paymentMode: "freeTrial", price: 0.0, subscriptionPeriod: "P1W")
                ]),
                SKSubscription(productID: "com.app.pro_yearly", referenceName: "Pro Yearly Plan", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Pro Yearly Plan", description: "Annual discount plan.")
                ], price: 79.99, subscriptionGroupID: "Pro Group", subscriptionPeriod: "P1Y", introductoryOffers: [
                    SKIntroductoryOffer(numberOfPeriods: 1, paymentMode: "freeTrial", price: 0.0, subscriptionPeriod: "P2W")
                ])
            ])
            activeConfig.subscriptionGroups = [proGroup]
            activeConfig.nonRenewingSubscriptions = []

        case "Consumables / Tips":
            activeConfig.products = [
                SKProduct(productID: "com.app.tip_small", referenceName: "Small Tip Don", type: "Consumable", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Small Tip", description: "Support the developer with a small tip!")
                ], price: 0.99),
                SKProduct(productID: "com.app.tip_large", referenceName: "Large Tip Don", type: "Consumable", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Large Tip", description: "Show major support with a generous tip!")
                ], price: 4.99)
            ]
            activeConfig.subscriptionGroups = []
            activeConfig.nonRenewingSubscriptions = []

        case "Streaming Service":
            activeConfig.products = []
            let streamGroup = SKSubscriptionGroup(groupName: "Streaming Group", subscriptions: [
                SKSubscription(productID: "com.app.stream_basic", referenceName: "Basic Tier", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Basic Stream", description: "HD stream with ads.")
                ], price: 5.99, subscriptionGroupID: "Streaming Group", subscriptionPeriod: "P1M"),
                SKSubscription(productID: "com.app.stream_ultra", referenceName: "Ultra 4K Tier", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Ultra 4K Stream", description: "4K stream on 4 devices simultaneously.")
                ], price: 14.99, subscriptionGroupID: "Streaming Group", subscriptionPeriod: "P1M")
            ])
            activeConfig.subscriptionGroups = [streamGroup]
            activeConfig.nonRenewingSubscriptions = []

        case "Mixed Catalog":
            activeConfig.products = [
                SKProduct(productID: "com.app.ad_free_lifetime", referenceName: "Ad Free Lifetime", type: "NonConsumable", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Ad Free Lifetime", description: "Remove all advertisements forever.")
                ], price: 4.99),
                SKProduct(productID: "com.app.coins_pack", referenceName: "1000 Coins Pack", type: "Consumable", localizations: [
                    SKLocalization(locale: "en_US", displayName: "1000 Coins Pack", description: "Buy 1000 gold coins for in-game purchases.")
                ], price: 2.99)
            ]
            let vipGroup = SKSubscriptionGroup(groupName: "VIP Club", subscriptions: [
                SKSubscription(productID: "com.app.vip_monthly", referenceName: "Monthly VIP Pass", localizations: [
                    SKLocalization(locale: "en_US", displayName: "VIP Monthly Club", description: "Unlock exclusive features and daily rewards.")
                ], price: 12.99, subscriptionGroupID: "VIP Club", subscriptionPeriod: "P1M", introductoryOffers: [
                    SKIntroductoryOffer(numberOfPeriods: 1, paymentMode: "freeTrial", price: 0.0, subscriptionPeriod: "P1W")
                ])
            ])
            activeConfig.subscriptionGroups = [vipGroup]
            activeConfig.nonRenewingSubscriptions = [
                SKNonRenewingSubscription(productID: "com.app.pass_3months", referenceName: "3 Month Seasonal Pass", localizations: [
                    SKLocalization(locale: "en_US", displayName: "Seasonal 3 Month Pass", description: "Get seasonal benefits for 3 months.")
                ], price: 9.99)
            ]

        default:
            break
        }
        StoreKitSimulationService.shared.log("Applied template: '\(name)' to the active workspace.")
    }
}

@Observable
@MainActor
public final class StoreKitWorkspaceManager {
    public static let shared = StoreKitWorkspaceManager()

    public var activeConfig: StoreKitConfig = StoreKitConfig()
    public var recentFiles: [URL] = []

    private init() {
        loadRecents()
    }

    private func loadRecents() {
        if let paths = UserDefaults.standard.stringArray(forKey: "com.swiftcode.storekit.recents") {
            self.recentFiles = paths.compactMap { URL(fileURLWithPath: $0) }
        }
    }

    private func saveRecents() {
        let paths = recentFiles.map { $0.path }
        UserDefaults.standard.set(paths, forKey: "com.swiftcode.storekit.recents")
    }

    public func addRecent(url: URL) {
        recentFiles.removeAll { $0 == url || $0.path == url.path }
        recentFiles.insert(url, at: 0)
        recentFiles = Array(recentFiles.prefix(10))
        saveRecents()
    }
}
